import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'flclash_core_api.dart';

/// Host-side pipe for the UNMODIFIED FlClash core RPC method dispatcher.
/// Native bridge: FlClash/core/server.go's little-endian length framed JSON.
/// No proxy algorithms, profile conversion or request routing live here.
class FlClashWindowsTransport implements FlClashCoreTransport {
  FlClashWindowsTransport({String? binaryPath})
      : binaryPath = binaryPath ??
          '${File(Platform.resolvedExecutable).parent.path}'
              '${Platform.pathSeparator}core${Platform.pathSeparator}FlClashCore.exe';

  final String binaryPath;
  Process? _process;
  Future<void>? _starting;
  StreamSubscription<List<int>>? _stdout;
  Uint8List _buffer = Uint8List(0);
  final Map<String, Completer<String?>> _waiting = {};
  bool _disposed = false;

  Future<void> _start() async {
    if (_disposed) throw StateError('FlClash backend is closed');
    if (_process != null) return;
    final currentStart = _starting;
    if (currentStart != null) return currentStart;
    final completer = Completer<void>();
    _starting = completer.future;
    try {
      if (!await File(binaryPath).exists()) {
        throw StateError('FlClash network backend missing');
      }
      final process = await Process.start(binaryPath, ['--vela-stdio'],
          runInShell: false);
      _process = process;
      _stdout = process.stdout.listen(_receive, onError: _failAll,
          onDone: () => _failAll(StateError('FlClash backend stream closed')));
      // Keep stderr drained but do not print subscription tokens or node keys.
      process.stderr.listen((_) {});
      unawaited(process.exitCode.then((code) {
        if (_process == process) _process = null;
        _failAll(StateError('FlClash backend exited: $code'));
      }));
      completer.complete();
    } catch (e, stack) {
      completer.completeError(e, stack);
    } finally {
      _starting = null;
    }
    return completer.future;
  }

  void _failAll(Object error) {
    final pending = _waiting.values.toList();
    _waiting.clear();
    for (final waiter in pending) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  void _receive(List<int> chunk) {
    final joined = BytesBuilder(copy: false)
      ..add(_buffer)
      ..add(chunk);
    final bytes = joined.toBytes();
    var cursor = 0;
    while (bytes.length - cursor >= 4) {
      final len = ByteData.sublistView(bytes, cursor, cursor + 4)
          .getUint32(0, Endian.little);
      if (len == 0 || len > 16 * 1024 * 1024) {
        _failAll(StateError('Invalid FlClash IPC frame'));
        _process?.kill();
        return;
      }
      if (bytes.length - cursor - 4 < len) break;
      final text = utf8.decode(bytes.sublist(cursor + 4, cursor + 4 + len));
      cursor += len + 4;
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        continue;
      }
      // Core events (log, delay, routeChanged, etc.) have no id. Do not
      // confuse them with method responses and never expose private logs.
      if (decoded is! Map || decoded['id'] is! String) continue;
      final id = decoded['id'] as String;
      final completer = _waiting.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(text);
      }
    }
    _buffer = Uint8List.fromList(bytes.sublist(cursor));
  }

  @override
  Future<String?> invoke(String requestJson) async {
    await _start();
    if (_disposed) throw StateError('FlClash backend is closed');
    final request = jsonDecode(requestJson);
    if (request is! Map || request['id'] is! String) {
      throw const FormatException('FlClash request has no RPC id');
    }
    final id = request['id'] as String;
    if (_waiting.containsKey(id)) {
      throw StateError('Duplicate FlClash request id');
    }
    final data = utf8.encode(requestJson);
    if (data.isEmpty || data.length > 16 * 1024 * 1024) {
      throw const FormatException('FlClash RPC request too large');
    }
    final waiter = Completer<String?>();
    _waiting[id] = waiter;
    final header = ByteData(4)..setUint32(0, data.length, Endian.little);
    try {
      _process!.stdin.add(header.buffer.asUint8List());
      _process!.stdin.add(data);
      await _process!.stdin.flush();
      return await waiter.future.timeout(const Duration(minutes: 2));
    } finally {
      _waiting.remove(id);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failAll(StateError('FlClash backend closed'));
    await _stdout?.cancel();
    _process?.kill();
    _process = null;
  }
}
