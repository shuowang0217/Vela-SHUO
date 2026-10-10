import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_core_config.dart';

enum VelaCorePhase { idle, checking, starting, listening, stopping, failed }

/// Run an external core without handing its stdout/stderr to application logs.
abstract class VelaCoreHandle {
  Future<int> get exitCode;
  void kill();
}

abstract class VelaCoreRunner {
  Future<void> check(String binary, String config);
  Future<void> assertPortFree(int port);
  Future<VelaCoreHandle> launch(String binary, String config);
  Future<bool> awaitLocalListener(int port);
}

class _NativeHandle implements VelaCoreHandle {
  _NativeHandle(this.process);
  final Process process;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  void kill() => process.kill();
}

class VelaNativeCoreRunner implements VelaCoreRunner {
  const VelaNativeCoreRunner();

  static Future<Process> _spawn(
    String binary, String command, String config,
  ) async {
    final process = await Process.start(binary, [command, '-c', config],
        runInShell: false, workingDirectory: File(config).parent.path);
    // Drain outputs, never persist untrusted core logs or proxy credentials.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return process;
  }

  @override
  Future<void> check(String binary, String config) async {
    final process = await _spawn(binary, 'check', config);
    try {
      final code = await process.exitCode.timeout(const Duration(seconds:12));
      if (code != 0) {
        throw const FormatException('内核配置自检未通过，请检查配置版本与协议');
      }
    } on TimeoutException {
      process.kill();
      throw const FormatException('内核配置自检超时');
    }
  }

  @override
  Future<void> assertPortFree(int port) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port,
        shared: false);
    await socket.close();
  }

  @override
  Future<VelaCoreHandle> launch(String binary, String config) async =>
      _NativeHandle(await _spawn(binary, 'run', config));

  @override
  Future<bool> awaitLocalListener(int port) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 8)) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4, port,
          timeout: const Duration(milliseconds: 250),
        );
        socket.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return false;
  }
}

/// Real LOCAL listener state, deliberately separate from VelaDemoController.
/// Never changes Windows proxy settings or claims an Internet tunnel exists.
class VelaCoreController extends ChangeNotifier {
  VelaCoreController({VelaCoreRunner? runner, bool? supported})
      : _runner = runner ?? const VelaNativeCoreRunner(),
        supported = supported ?? Platform.isWindows;

  final VelaCoreRunner _runner;
  final bool supported;
  VelaCorePhase _phase = VelaCorePhase.idle;
  String? _binary;
  String? _configPath;
  VelaLocalCoreConfig? _config;
  VelaCoreHandle? _process;
  String? _error;
  int _generation = 0;
  bool _disposed = false;

  VelaCorePhase get phase => _phase;
  String? get error => _error;
  bool get hasConfig => _config != null;
  bool get hasCore => _binary != null;
  bool get busy => _phase == VelaCorePhase.checking ||
      _phase == VelaCorePhase.starting ||
      _phase == VelaCorePhase.stopping;
  bool get isListening => _phase == VelaCorePhase.listening;
  int? get localPort => _config?.localPort;
  String get localAddress =>
      _config == null ? '—' : '127.0.0.1:${_config!.localPort}';
  String get phaseLabel => switch (_phase) {
    VelaCorePhase.idle => '本地代理未启动',
    VelaCorePhase.checking => '正在验证配置…',
    VelaCorePhase.starting => '正在启动本地代理…',
    VelaCorePhase.listening => '本地端口已监听（非外网连通验证）',
    VelaCorePhase.stopping => '正在关闭…',
    VelaCorePhase.failed => '代理内核启动失败',
  };

  void _update(VelaCorePhase phase, [String? message]) {
    _phase = phase;
    _error = message;
    if (!_disposed) notifyListeners();
  }

  /// The original JSON is read-only and never copied into preferences/logs.
  Future<bool> chooseConfig(String path) async {
    if (busy || isListening) return false;
    try {
      final file = File(path);
      final length = await file.length();
      if (length > VelaLocalCoreConfig.maxBytes) {
        _update(VelaCorePhase.failed, '配置文件不能超过 2 MB');
        return false;
      }
      final parsed = VelaLocalCoreConfig.parse(await file.readAsString());
      _configPath = file.absolute.path;
      _config = parsed;
      _update(VelaCorePhase.idle);
      return true;
    } on FormatException catch (e) {
      // Only FormatException messages authored inside our validator.
      _update(VelaCorePhase.failed, e.message);
      return false;
    } catch (_) {
      _update(VelaCorePhase.failed, '无法读取所选配置文件');
      return false;
    }
  }

  Future<bool> chooseBinary(String path) async {
    if (busy || isListening) return false;
    try {
      final file = File(path);
      if (file.uri.pathSegments.last.toLowerCase() != 'sing-box.exe' ||
          !await file.exists()) {
        _update(VelaCorePhase.failed, '请选择可信来源的 sing-box.exe');
        return false;
      }
      _binary = file.absolute.path;
      _update(VelaCorePhase.idle);
      return true;
    } catch (_) {
      _update(VelaCorePhase.failed, '无法读取代理内核程序');
      return false;
    }
  }

  Future<bool> start() async {
    if (!supported || busy || isListening) return false;
    final binary = _binary;
    final path = _configPath;
    final config = _config;
    if (binary == null || path == null || config == null) {
      _update(VelaCorePhase.failed, '请先选择 sing-box.exe 和本地 JSON 配置');
      return false;
    }
    final generation = ++_generation;
    _update(VelaCorePhase.checking);
    try {
      // Re-read at start in case the JSON file was changed after selection.
      final source = await File(path).readAsString();
      final current = VelaLocalCoreConfig.parse(source);
      if (current.localPort != config.localPort) {
        throw const FormatException('配置端口已改变，请重新导入');
      }
      if (generation != _generation) return false;
      await _runner.check(binary, path);
      if (generation != _generation) return false;
      await _runner.assertPortFree(config.localPort);
      if (generation != _generation) return false;
      _update(VelaCorePhase.starting);
      final handle = await _runner.launch(binary, path);
      if (generation != _generation) {
        handle.kill();
        return false;
      }
      _process = handle;
      unawaited(handle.exitCode.then((_) {
        if (identical(_process, handle) && generation == _generation) {
          _process = null;
          _update(VelaCorePhase.failed, '内核进程已退出；本地代理不可用');
        }
      }, onError: (Object _) {
        if (identical(_process, handle) && generation == _generation) {
          _process = null;
          _update(VelaCorePhase.failed, '内核进程异常退出');
        }
      }));
      final ready = await _runner.awaitLocalListener(config.localPort);
      if (generation != _generation) {
        handle.kill();
        return false;
      }
      if (!ready || !identical(_process, handle)) {
        handle.kill();
        _process = null;
        _update(VelaCorePhase.failed, '未检测到 127.0.0.1 本地监听端口');
        return false;
      }
      _update(VelaCorePhase.listening);
      return true;
    } on FormatException catch (e) {
      _process?.kill();
      _process = null;
      if (generation == _generation) _update(VelaCorePhase.failed, e.message);
    } on SocketException {
      if (generation == _generation) {
        _update(VelaCorePhase.failed, '本地端口被其他程序占用');
      }
    } catch (_) {
      _process?.kill();
      _process = null;
      if (generation == _generation) {
        _update(VelaCorePhase.failed, '无法启动代理内核，请核对程序、配置与端口');
      }
    }
    return false;
  }

  /// Stop owns only the process started by Vela-SHUO.
  /// It does not touch the user's existing system/network proxy settings.
  Future<void> stop() async {
    ++_generation;
    final handle = _process;
    _process = null;
    if (handle == null) {
      _update(VelaCorePhase.idle);
      return;
    }
    _update(VelaCorePhase.stopping);
    handle.kill();
    try {
      await handle.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      // Stop is best-effort; Windows may refuse process termination.
    }
    if (!_disposed) _update(VelaCorePhase.idle);
  }

  @override
  void dispose() {
    ++_generation;
    _process?.kill();
    _process = null;
    _disposed = true;
    super.dispose();
  }
}
