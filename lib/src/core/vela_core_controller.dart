import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_core_config.dart';
import '../mihomo/vela_mihomo_selector.dart';
import 'vela_windows_job.dart';

enum VelaCorePhase { idle, checking, starting, listening, stopping, failed }
enum VelaNodeSwitchResult { success, restored, unverified }

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

/// Real HTTPS request through the local HTTP proxy. A listening TCP socket
/// by itself is not evidence that an external node can reach the Internet.
abstract class VelaRemoteProbe {
  Future<bool> verify(int localPort);
}

class VelaHttpsRemoteProbe implements VelaRemoteProbe {
  const VelaHttpsRemoteProbe();

  @override
  Future<bool> verify(int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 7)
      ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
    try {
      final request = await client.getUrl(
        Uri.parse('https://cp.cloudflare.com/generate_204'),
      ).timeout(const Duration(seconds: 9));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 9),
      );
      await response.drain<void>();
      return response.statusCode == 204;
    } catch (_) {
      return false; // No error text or credentials enter logs.
    } finally {
      client.close(force: true);
    }
  }
}

class _NativeHandle implements VelaCoreHandle {
  _NativeHandle(this.process, this.job) {
    unawaited(process.exitCode.then((_) => job?.close(),
        onError: (Object _) => job?.close()));
  }

  final Process process;
  final VelaWindowsJob? job;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  void kill() {
    job?.close(); // OS kills the child when the final Job handle closes.
    process.kill();
  }
}

class VelaNativeCoreRunner implements VelaCoreRunner {
  const VelaNativeCoreRunner();

  static Future<Process> _spawn(
    String binary, bool check, String config,
  ) async {
    final directory = File(config).parent.path;
    final process = await Process.start(binary,
        [if (check) '-t', '-d', directory, '-f', config],
        runInShell: false, workingDirectory: directory);
    // Drain outputs, never persist untrusted core logs or proxy credentials.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return process;
  }

  @override
  Future<void> check(String binary, String config) async {
    final process = await _spawn(binary, true, config);
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
  Future<VelaCoreHandle> launch(String binary, String config) async {
    final child = await _spawn(binary, false, config);
    try {
      // Refuse to run an uncontained Windows proxy; forced UI termination
      // must never leave a lingering Mihomo owned by this app.
      final job = Platform.isWindows ? VelaWindowsJob.attach(child.pid) : null;
      return _NativeHandle(child, job);
    } catch (_) {
      child.kill();
      rethrow;
    }
  }

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
  VelaCoreController({
    VelaCoreRunner? runner,
    bool? supported,
    String? bundledCorePath,
    Directory? managedProfileDirectory,
    VelaRemoteProbe? remoteProbe,
    VelaMihomoSelectorApi? selectorApi,
  })  : _selectorApi = selectorApi ?? const VelaLoopbackMihomoSelectorApi(),
        _runner = runner ?? const VelaNativeCoreRunner(),
        _remoteProbe = remoteProbe ?? const VelaHttpsRemoteProbe(),
        supported = supported ?? Platform.isWindows,
        _bundledCorePath = bundledCorePath,
        _managedProfileDirectory = managedProfileDirectory;

  final VelaCoreRunner _runner;
  final VelaMihomoSelectorApi _selectorApi;
  bool _switching = false;
  final VelaRemoteProbe _remoteProbe;
  bool _remoteVerified = false;
  bool _probing = false;
  bool get remoteVerified => _remoteVerified;
  /// Native FlClash opens the listener before checking public test URLs.
  /// Legacy standalone cores keep the stricter preflight behavior.
  bool get requiresRemoteProbeBeforeTakeover => true;
  bool get probing => _probing;
  final bool supported;
  final String? _bundledCorePath;
  final Directory? _managedProfileDirectory;
  bool _initialized = false;
  bool _directTestProfile = false;
  bool get directTestProfile => _directTestProfile;
  bool get usingBundledCore => _binary != null &&
      _binary == _defaultCorePath;
  String get _defaultCorePath => _bundledCorePath ??
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}core${Platform.pathSeparator}mihomo.exe';

  Directory? get _profileFolder {
    if (_managedProfileDirectory != null) return _managedProfileDirectory;
    if (!Platform.isWindows) return null;
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.trim().isEmpty) return null;
    return Directory(
      '$root${Platform.pathSeparator}Vela-SHUO'
      '${Platform.pathSeparator}Profiles',
    );
  }

  /// Prepare a verified, bundled core and a local DIRECT test profile.
  /// No process is started, no system setting is touched, and no
  /// external subscriptions are generated or downloaded.
  Future<void> initialize() async {
    if (_initialized || !supported || _disposed) return;
    _initialized = true;
    if (await File(_defaultCorePath).exists()) {
      _binary = File(_defaultCorePath).absolute.path;
    }
    await _purgeOldRemoteProfile();
    await useLocalDirectProfile();
    if (!_disposed) notifyListeners();
  }

  /// The previous run's generated secret-bearing file is never trusted on
  /// startup. Remove it before any user-provided subscription is imported.
  Future<void> _purgeOldRemoteProfile() async {
    final folder = _profileFolder;
    if (folder == null) return;
    try {
      final old = File(
        '${folder.path}${Platform.pathSeparator}subscription-active.json',
      );
      if (await old.exists()) await old.delete();
    } catch (_) {
      // A failure is reported only if a later import needs this directory.
    }
  }

  /// Build a single-node local proxy profile from a supported subscription.
  /// This method intentionally refuses to alter profiles while connected.
  Future<bool> useRemoteSubscriptionProfile(String source) async {
    if (!supported || busy || isListening) return false;
    final folder = _profileFolder;
    if (folder == null) {
      _update(VelaCorePhase.failed, '没有可用的配置目录');
      return false;
    }
    try {
      final validated = VelaLocalCoreConfig.parse(source);
      await folder.create(recursive: true);
      final staged = File(
        '${folder.path}${Platform.pathSeparator}subscription-stage.json',
      );
      final target = File(
        '${folder.path}${Platform.pathSeparator}subscription-active.json',
      );
      // Credentials are written only to the local user profile, never to
      // diagnostics, preferences or the application installation folder.
      await staged.writeAsString(source, flush: true);
      if (await target.exists()) await target.delete();
      await staged.rename(target.path);
      _configPath = target.path;
      _config = validated;
      _directTestProfile = false;
      _update(VelaCorePhase.idle);
      return true;
    } catch (_) {
      _update(VelaCorePhase.failed, '无法保存节点配置');
      return false;
    }
  }

  /// This profile is only for verifying the bundled binary/loopback port.
  /// Outbound is DIRECT, not a foreign proxy node or VPN.
  Future<bool> useLocalDirectProfile() async {
    if (busy || isListening) return false;
    final folder = _profileFolder;
    if (folder == null) {
      _update(VelaCorePhase.failed, '没有可用的本地配置目录');
      return false;
    }
    try {
      await folder.create(recursive: true);
      final file = File(
        '${folder.path}${Platform.pathSeparator}local-direct.json',
      );
      // This file never contains credentials or subscription addresses.
      // Write our known-safe content to avoid accidentally using an old
      // file with the same name from a previous release.
      const source = '''
{
  "mixed-port": 20808,
  "bind-address": "127.0.0.1",
  "allow-lan": false,
  "mode": "rule",
  "log-level": "warning",
  "ipv6": false,
  "proxies": [],
  "proxy-groups": [],
  "rules": ["MATCH,DIRECT"]
}
''';
      await file.writeAsString(source, flush: true);
      final validated = VelaLocalCoreConfig.parse(source);
      _config = validated;
      _configPath = file.absolute.path;
      _directTestProfile = true;
      _update(VelaCorePhase.idle);
      return true;
    } catch (_) {
      _update(VelaCorePhase.failed, '无法创建本机直连测试配置');
      return false;
    }
  }
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
  /// Read-only executable path for disposable node benchmarks.
  String? get benchmarkCorePath => _binary;

  bool get busy => _switching || _phase == VelaCorePhase.checking ||
      _phase == VelaCorePhase.starting ||
      _phase == VelaCorePhase.stopping;
  bool get isListening => _phase == VelaCorePhase.listening;

  /// Authenticated, bounded loopback-only Mihomo /connections totals.
  /// Does not expose the API secret or per-connection metadata to widgets.
  Future<(int, int)?> readTrafficCounters() async {
    final config = _config;
    if (_disposed || !isListening || !_remoteVerified ||
        config?.apiPort == null || config?.apiSecret == null) {
      return null;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri.parse(
          'http://127.0.0.1:${config!.apiPort}/connections');
      final req = await client.getUrl(uri)
          .timeout(const Duration(seconds: 3));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader,
          'Bearer ${config.apiSecret}');
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != HttpStatus.ok || res.isRedirect ||
          res.contentLength > 2 * 1024 * 1024) {
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 3))) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          return null;
        }
        bytes.addAll(chunk);
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map) return null;
      final up = json['uploadTotal'];
      final down = json['downloadTotal'];
      if (up is! int || down is! int || up < 0 || down < 0) {
        return null;
      }
      return (up, down);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
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
    if (phase != VelaCorePhase.listening) _remoteVerified = false;
    _phase = phase;
    _error = message;
    if (!_disposed) notifyListeners();
  }

  /// The original JSON is read-only and never copied into preferences/logs.
  Future<bool> chooseConfig(String path) async {
    if (busy || isListening) return false;
    // Never silently fall back to a previous profile after a failed import.
    _config = null;
    _configPath = null;
    _directTestProfile = false;
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
      _directTestProfile = false;
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
      if (file.uri.pathSegments.last.toLowerCase() != 'mihomo.exe' ||
          !await file.exists()) {
        _update(VelaCorePhase.failed, '请选择可信来源的 mihomo.exe');
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
      _update(VelaCorePhase.failed, '内核或配置尚未就绪，请检查便携包是否完整');
      return false;
    }
    final generation = ++_generation;
    _update(VelaCorePhase.checking);
    try {
      // Re-read at start in case the JSON file was changed after selection.
      final file = File(path);
      if (await file.length() > VelaLocalCoreConfig.maxBytes) {
        throw const FormatException('配置文件超过 2 MB 限制');
      }
      final source = await file.readAsString();
      final current = VelaLocalCoreConfig.parse(source);
      if (current.localPort != config.localPort ||
          current.apiPort != config.apiPort ||
          current.apiSecret != config.apiSecret ||
          !listEquals(current.selectorNames, config.selectorNames)) {
        throw const FormatException('运行配置或控制密钥已改变，请重新导入');
      }
      if (generation != _generation) return false;
      await _runner.check(binary, path);
      if (generation != _generation) return false;
      await _runner.assertPortFree(config.localPort);
      if (config.apiPort != null) {
        await _runner.assertPortFree(config.apiPort!);
      }
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

  /// Verify that an external HTTPS endpoint is reached THROUGH the chosen
  /// proxy with normal certificate validation, not through direct fallback.
  Future<bool> verifyRemote() async {
    if (!isListening || _directTestProfile || _probing || _disposed) {
      return false;
    }
    final run = _generation;
    _probing = true;
    _remoteVerified = false;
    if (!_disposed) notifyListeners();
    bool success;
    try {
      success = await _remoteProbe.verify(_config!.localPort);
    } catch (_) {
      success = false;
    }
    if (_disposed || run != _generation || !isListening) return false;
    _probing = false;
    _remoteVerified = success;
    if (!_disposed) notifyListeners();
    return success;
  }

  /// Change only the authenticated Mihomo selector, leaving WinINet
  /// and the listening mixed port untouched. A failed remote HTTPS check
  /// rolls back the previous selector before reporting any success.
  Future<VelaNodeSwitchResult> switchActiveNode({
    required String currentName, required String nextName,
  }) async {
    final config = _config;
    if (_disposed || config == null || !isListening || !_remoteVerified ||
        _directTestProfile || _probing || _switching ||
        config.apiPort == null || config.apiSecret == null ||
        !config.selectorNames.contains(currentName) ||
        !config.selectorNames.contains(nextName)) {
      return VelaNodeSwitchResult.unverified;
    }
    if (currentName == nextName) return VelaNodeSwitchResult.success;
    final port = config.apiPort!;
    final secret = config.apiSecret!;
    final generation = _generation;
    _switching = true;
    _probing = true;
    if (!_disposed) notifyListeners();
    try {
      // Reject unexpected external changes rather than overwriting them.
      if (await _selectorApi.active(port, secret) != currentName) {
        _remoteVerified = false;
        return VelaNodeSwitchResult.unverified;
      }
      final applied = await _selectorApi.select(port, secret, nextName);
      if (applied &&
          await _selectorApi.active(port, secret) == nextName &&
          generation == _generation && isListening &&
          await _remoteProbe.verify(config.localPort)) {
        return VelaNodeSwitchResult.success;
      }
      // A timed-out request might have changed the selector anyway.
      final restored = await _selectorApi.select(port, secret, currentName);
      if (restored &&
          await _selectorApi.active(port, secret) == currentName &&
          generation == _generation && isListening &&
          await _remoteProbe.verify(config.localPort)) {
        return VelaNodeSwitchResult.restored;
      }
      _remoteVerified = false;
      return VelaNodeSwitchResult.unverified;
    } catch (_) {
      // If probing itself throws after PUT, restore the previous route.
      try {
        if (await _selectorApi.select(port, secret, currentName) &&
            await _selectorApi.active(port, secret) == currentName &&
            generation == _generation && isListening &&
            await _remoteProbe.verify(config.localPort)) {
          return VelaNodeSwitchResult.restored;
        }
      } catch (_) {
        // Unverified rollback must never be reported as connected.
      }
      _remoteVerified = false;
      return VelaNodeSwitchResult.unverified;
    } finally {
      _probing = false;
      _switching = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Stop owns only the process started by Vela-SHUO.
  /// It does not touch the user's existing system/network proxy settings.
  Future<void> stop() async {
    ++_generation;
    final handle = _process;
    _process = null;
    _probing = false;
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
