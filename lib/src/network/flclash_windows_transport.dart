import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'flclash_core_api.dart';

/// Windows host transport for the ORIGINAL FlClash Go server.go RPC protocol.
///
/// The Go network algorithms and message frames are unchanged; Vela hosts an
/// ephemeral authenticated loopback socket so stdout/stderr never mix with
/// binary RPC frames. No network credentials or subscriptions are logged.
class FlClashWindowsTransport implements FlClashCoreTransport {
  FlClashWindowsTransport({String? binaryPath})
      : binaryPath = binaryPath ??
          '${File(Platform.resolvedExecutable).parent.path}'
              '${Platform.pathSeparator}core${Platform.pathSeparator}FlClashCore.exe';

  final String binaryPath;
  Process? _process;
  Socket? _socket;
  StreamSubscription<List<int>>? _incoming;
  Future<void>? _starting;
  Uint8List _buffer = Uint8List(0);
  Uint8List? _token;
  int _tokenBytesReceived = 0;
  Completer<void>? _handshake;
  final Map<String, Completer<String?>> _waiting = {};
  bool _disposed = false;

  Future<void> _start() {
    if (_disposed) return Future.error(StateError('FlClash transport closed'));
    if (_socket != null && _tokenBytesReceived == 32) {
      return Future.value();
    }
    return _starting ??= _connect().whenComplete(() => _starting = null);
  }

  Future<void> _connect() async {
    if (!await File(binaryPath).exists()) {
      throw StateError('FlClash Go backend executable missing');
    }
    final listener = await ServerSocket.bind(
        InternetAddress.loopbackIPv4, 0, shared: false);
    try {
      final random = Random.secure();
      final token = Uint8List.fromList(
          List<int>.generate(32, (_) => random.nextInt(256)));
      final tokenHex = token
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      // Accept only a local connection presenting the 256-bit rendezvous key.
      // The temporary host listener is closed immediately after handshake.
      final accepting = listener.first.timeout(const Duration(seconds: 12));
      final process = await Process.start(binaryPath, [
        '--vela-loopback=$tokenHex@127.0.0.1:${listener.port}',
      ], runInShell: false);
      _process = process;
      process.stdout.listen((_) {});
      process.stderr.listen((_) {});
      unawaited(process.exitCode.then((code) {
        if (_process == process) _process = null;
        _socket?.destroy();
        _failAll(StateError('FlClash Go exited: $code'));
      }));

      final socket = await accepting;
      _socket = socket;
      _token = token;
      _tokenBytesReceived = 0;
      _handshake = Completer<void>();
      _incoming = socket.listen(_onData, onError: (Object error) {
        _failAll(error);
        socket.destroy();
      }, onDone: () {
        _socket = null;
        _failAll(StateError('FlClash RPC socket disconnected'));
        _process?.kill();
      });
      await _handshake!.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _socket?.destroy();
      _socket = null;
      _process?.kill();
      _process = null;
      rethrow;
    } finally {
      await listener.close();
    }
  }

  void _failAll(Object error) {
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(error);
    }
    final pending = _waiting.values.toList();
    _waiting.clear();
    for (final waiter in pending) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  void _onData(List<int> chunk) {
    var offset = 0;
    final token = _token;
    if (token == null) {
      _socket?.destroy();
      return;
    }
    while (_tokenBytesReceived < token.length && offset < chunk.length) {
      if (chunk[offset] != token[_tokenBytesReceived]) {
        _failAll(StateError('FlClash IPC authentication rejected'));
        _socket?.destroy();
        return;
      }
      ++_tokenBytesReceived;
      ++offset;
    }
    if (_tokenBytesReceived != token.length) return;
    if (_handshake case final handshake? when !handshake.isCompleted) {
      handshake.complete();
    }
    if (offset < chunk.length) {
      _receive(chunk.sublist(offset));
    }
  }

  void _receive(List<int> chunk) {
    final collector = BytesBuilder(copy: false)
      ..add(_buffer)
      ..add(chunk);
    final bytes = collector.toBytes();
    var cursor = 0;
    while (bytes.length - cursor >= 4) {
      final length = ByteData.sublistView(bytes, cursor, cursor + 4)
          .getUint32(0, Endian.little);
      if (length == 0 || length > 16 * 1024 * 1024) {
        _failAll(StateError('Invalid FlClash RPC frame'));
        _socket?.destroy();
        return;
      }
      if (bytes.length - cursor - 4 < length) break;
      final payload = bytes.sublist(cursor + 4, cursor + 4 + length);
      cursor += length + 4;
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(payload));
      } on FormatException {
        _failAll(StateError('FlClash RPC returned invalid JSON'));
        _socket?.destroy();
        return;
      }
      // Native events have a "method" but no request id.
      if (decoded is! Map || decoded['id'] is! String) continue;
      final id = decoded['id'] as String;
      final waiter = _waiting.remove(id);
      if (waiter != null && !waiter.isCompleted) {
        waiter.complete(utf8.decode(payload));
      }
    }
    _buffer = Uint8List.fromList(bytes.sublist(cursor));
  }

  @override
  Future<String?> invoke(String requestJson) async {
    await _start();
    if (_disposed) throw StateError('FlClash transport closed');
    final request = jsonDecode(requestJson);
    if (request is! Map || request['id'] is! String) {
      throw const FormatException('FlClash RPC request id missing');
    }
    final id = request['id'] as String;
    if (_waiting.containsKey(id)) {
      throw StateError('Duplicate FlClash RPC request id');
    }
    final data = utf8.encode(requestJson);
    if (data.isEmpty || data.length > 16 * 1024 * 1024) {
      throw const FormatException('FlClash RPC request too large');
    }
    final socket = _socket;
    if (socket == null) throw StateError('FlClash RPC socket unavailable');
    final waiter = Completer<String?>();
    _waiting[id] = waiter;
    final header = ByteData(4)..setUint32(0, data.length, Endian.little);
    try {
      socket.add(header.buffer.asUint8List());
      socket.add(data);
      await socket.flush();
      return await waiter.future.timeout(const Duration(minutes: 2));
    } finally {
      _waiting.remove(id);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failAll(StateError('FlClash backend closed'));
    await _incoming?.cancel();
    _socket?.destroy();
    _socket = null;
    _process?.kill();
    _process = null;
  }
}
