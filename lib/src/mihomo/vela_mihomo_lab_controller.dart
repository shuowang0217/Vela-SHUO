// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/vela_core_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import 'vela_mihomo_config.dart';

enum VelaMihomoPhase { idle, starting, ready, stopping, failed }

abstract class VelaMihomoProcess {
  Future<int> get exitCode;
  void kill();
}

abstract class VelaMihomoRunner {
  Future<void> check(String exe, String config, String dir);
  Future<VelaMihomoProcess> launch(String exe, String config, String dir);
  Future<void> assertPortsFree();
}

class VelaNativeMihomoProcess implements VelaMihomoProcess {
  VelaNativeMihomoProcess(this.process);
  final Process process;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  void kill() => process.kill();
}

class VelaNativeMihomoRunner implements VelaMihomoRunner {
  const VelaNativeMihomoRunner();

  static Future<Process> _spawn(String exe, List<String> args, String dir) async {
    final p = await Process.start(exe, args, runInShell: false,
        workingDirectory: dir);
    // The core may echo private addresses or tokens: discard both streams.
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return p;
  }

  @override
  Future<void> check(String exe, String config, String dir) async {
    final process = await _spawn(exe, ['-t', '-d', dir, '-f', config], dir);
    try {
      final status = await process.exitCode.timeout(const Duration(seconds: 20));
      if (status != 0) {
        throw const FormatException('Mihomo 配置检查失败，部分节点参数可能不兼容');
      }
    } on TimeoutException {
      process.kill();
      throw const FormatException('Mihomo 配置检查超时');
    }
  }

  @override
  Future<VelaMihomoProcess> launch(
      String exe, String config, String dir) async =>
      VelaNativeMihomoProcess(await _spawn(
        exe, ['-d', dir, '-f', config], dir,
      ));

  @override
  Future<void> assertPortsFree() async {
    for (final port in [
      VelaMihomoConfiguration.proxyPort,
      VelaMihomoConfiguration.apiPort,
    ]) {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4, port, shared: false,
      ).timeout(const Duration(seconds: 3));
      await socket.close();
    }
  }
}

/// Mihomo local REST API. Does not accept caller-supplied URLs/hosts, and
/// never transmits bearer credentials outside 127.0.0.1.
abstract class VelaMihomoApi {
  Future<String?> active(String secret);
  Future<bool> select(String secret, String node);
}

class VelaLoopbackMihomoApi implements VelaMihomoApi {
  const VelaLoopbackMihomoApi();

  static const endpoint = 'http://127.0.0.1:20819/proxies/VELA_SELECT';

  @override
  Future<String?> active(String secret) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 4));
      request.followRedirects = false;
      request.headers.set('Authorization', 'Bearer ' + secret);
      final response = await request.close()
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 || response.isRedirect ||
          response.contentLength > 8192) { return null; }
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 4))) {
        if (bytes.length + part.length > 8192) { return null; }
        bytes.addAll(part);
      }
      final body = jsonDecode(utf8.decode(bytes));
      return body is Map && body['now'] is String
          ? body['now'] as String : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> select(String secret, String node) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.putUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 4));
      request.followRedirects = false;
      request.headers.set('Authorization', 'Bearer ' + secret);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({'name': node})));
      final response = await request.close()
          .timeout(const Duration(seconds: 4));
      await response.drain<void>();
      return !response.isRedirect &&
          (response.statusCode == 204 || response.statusCode == 200);
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

/// Experimental only. Uses different local ports and never touches WinINet,
/// Windows TUN, or the production sing-box connection coordinator.
class VelaMihomoLabController extends ChangeNotifier {
  VelaMihomoLabController({
    String? bundledBinary,
    Directory? stateDirectory,
    VelaMihomoRunner? runner,
    VelaMihomoApi? api,
    VelaRemoteProbe? remoteProbe,
    bool? supported,
  }) : supported = supported ?? Platform.isWindows,
       _path = bundledBinary ?? _defaultBinary(),
       _dir = stateDirectory ?? _defaultDirectory(),
       _runner = runner ?? const VelaNativeMihomoRunner(),
       _api = api ?? const VelaLoopbackMihomoApi(),
       _probe = remoteProbe ?? const VelaHttpsRemoteProbe();

  static String _defaultBinary() => File(Platform.resolvedExecutable)
      .parent.path + Platform.pathSeparator + 'core' +
      Platform.pathSeparator + 'mihomo.exe';

  static Directory _defaultDirectory() {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base != null && base.isNotEmpty) {
      return Directory(base + Platform.pathSeparator + 'Vela-SHUO' +
          Platform.pathSeparator + 'MihomoLab');
    }
    return Directory.systemTemp;
  }

  final bool supported;
  final String _path;
  final Directory _dir;
  final VelaMihomoRunner _runner;
  final VelaMihomoApi _api;
  final VelaRemoteProbe _probe;
  VelaMihomoProcess? _process;
  VelaMihomoConfiguration? _config;
  String? _secret;
  bool _binaryExists = false;
  bool _disposed = false;
  bool _busy = false;
  int _generation = 0;
  int? _selectedIndex;
  String? _error;
  VelaMihomoPhase _phase = VelaMihomoPhase.idle;

  bool get hasBinary => _binaryExists;
  bool get busy => _busy;
  bool get running => _phase == VelaMihomoPhase.ready;
  int? get selectedIndex => _selectedIndex;
  String? get selectedName => _selectedIndex == null ? null :
      _config?.nameFor(_selectedIndex!);
  String? get error => _error;
  VelaMihomoPhase get phase => _phase;
  int get compatibleCount => _config?.entries.length ?? 0;
  String get status => switch (_phase) {
    VelaMihomoPhase.idle => '实验内核未启动',
    VelaMihomoPhase.starting => 'Mihomo 配置检查与启动中…',
    VelaMihomoPhase.ready => 'Mihomo 实验代理运行中（独立端口）',
    VelaMihomoPhase.stopping => '正在停止实验内核…',
    VelaMihomoPhase.failed => 'Mihomo 实验测试失败',
  };

  void _notify([String? error]) {
    _error = error;
    if (!_disposed) { notifyListeners(); }
  }

  File get _file => File(_dir.path + Platform.pathSeparator + 'lab.json');

  Future<void> initialize() async {
    if (_disposed || !supported) { return; }
    _binaryExists = await File(_path).exists();
    // Prior sessions cannot be trusted: remove any old secret-bearing config.
    if (!_busy && _process == null && await _file.exists()) {
      try { await _file.delete(); } catch (_) {}
    }
    _notify();
  }

  Future<bool> start(List<VelaSubscriptionNode> nodes, int index) async {
    if (_disposed || !supported || !_binaryExists ||
        _busy || _process != null) { return false; }
    _busy = true;
    _phase = VelaMihomoPhase.starting;
    _notify();
    final generation = ++_generation;
    try {
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final secret = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final config = const VelaMihomoConfigBuilder().build(
        nodes, selectedIndex: index, secret: secret,
      );
      await _dir.create(recursive: true);
      await _file.writeAsString(config.configText, flush: true);
      await _runner.check(_path, _file.path, _dir.path);
      await _runner.assertPortsFree();
      final process = await _runner.launch(_path, _file.path, _dir.path);
      _process = process;
      _config = config;
      _secret = secret;
      _selectedIndex = index;
      unawaited(_observeExit(process, generation));
      final watch = Stopwatch()..start();
      String? current;
      while (watch.elapsed < const Duration(seconds: 12)) {
        current = await _api.active(secret);
        if (current != null) { break; }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (current != config.nameFor(index)) {
        throw StateError('Selector not ready');
      }
      if (!await _probe.verify(VelaMihomoConfiguration.proxyPort)) {
        throw StateError('External HTTPS probe failed');
      }
      _phase = VelaMihomoPhase.ready;
      _notify();
      return true;
    } catch (_) {
      await _killAndClear();
      _phase = VelaMihomoPhase.failed;
      _notify('Mihomo 启动或真实 HTTPS 验证失败；未修改 Windows 系统代理');
      return false;
    } finally {
      _busy = false;
      if (!_disposed) { notifyListeners(); }
    }
  }

  Future<bool> switchNode(int index) async {
    if (_disposed || _busy || !running || _config == null ||
        _secret == null) { return false; }
    final next = _config!.nameFor(index);
    if (next == null) {
      _notify('此节点的 Mihomo 参数尚不兼容');
      return false;
    }
    if (index == _selectedIndex) { return true; }
    _busy = true;
    _notify();
    try {
      final original = _config!.nameFor(_selectedIndex!);
      final changed = await _api.select(_secret!, next) &&
          (await _api.active(_secret!)) == next;
      if (!changed) {
        _notify('策略组选择失败，未确认切换成功');
        return false;
      }
      // A real remote HTTPS request is required before claiming success.
      if (!await _probe.verify(VelaMihomoConfiguration.proxyPort)) {
        if (original != null) {
          await _api.select(_secret!, original);
        }
        _notify('新节点 HTTPS 检测未通过；已尝试恢复上一节点');
        return false;
      }
      _selectedIndex = index;
      _notify();
      return true;
    } catch (_) {
      _notify('策略组切换异常，请检查 Mihomo 状态');
      return false;
    } finally {
      _busy = false;
      if (!_disposed) { notifyListeners(); }
    }
  }

  Future<void> _observeExit(VelaMihomoProcess process, int generation) async {
    try { await process.exitCode; } catch (_) {}
    if (_disposed || generation != _generation || _process != process) {
      return;
    }
    _process = null;
    _phase = VelaMihomoPhase.failed;
    _secret = null;
    _notify('Mihomo 实验内核意外退出，主 sing-box 不受影响');
    try { if (await _file.exists()) { await _file.delete(); } } catch (_) {}
  }

  Future<void> _killAndClear() async {
    final process = _process;
    _process = null;
    ++_generation;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) { process.kill(); }
    }
    _secret = null;
    _config = null;
    _selectedIndex = null;
    try { if (await _file.exists()) { await _file.delete(); } } catch (_) {}
  }

  Future<void> stop() async {
    if (_disposed || _busy) { return; }
    _busy = true;
    _phase = VelaMihomoPhase.stopping;
    _notify();
    try {
      await _killAndClear();
      _phase = VelaMihomoPhase.idle;
      _notify();
    } catch (_) {
      _phase = VelaMihomoPhase.failed;
      _notify('无法确认实验内核停止，请检查进程');
    } finally {
      _busy = false;
      if (!_disposed) { notifyListeners(); }
    }
  }

  /// Called on window disposal. No Windows system proxy is managed here.
  Future<void> shutdown() => _killAndClear();

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
