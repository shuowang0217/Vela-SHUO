// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class VelaProxySnapshot {
  const VelaProxySnapshot({required this.enabled, required this.server});
  final int? enabled;
  final String? server;

  Map<String, dynamic> toJson() => {'enabled': enabled, 'server': server};
  static VelaProxySnapshot fromJson(Map<String, dynamic> map) {
    if (map['enabled'] != null && map['enabled'] is! int ||
        map['server'] != null && map['server'] is! String) {
      throw const FormatException('Invalid proxy recovery state');
    }
    return VelaProxySnapshot(
      enabled: map['enabled'] as int?,
      server: map['server'] as String?,
    );
  }
  bool equals(VelaProxySnapshot value) =>
      enabled == value.enabled && server == value.server;
}

abstract class VelaWindowsProxyBackend {
  Future<VelaProxySnapshot> read();
  Future<bool> hasPac();
  Future<void> write(VelaProxySnapshot snapshot);
  Future<void> refresh();
}

class VelaRegistryProxyBackend implements VelaWindowsProxyBackend {
  const VelaRegistryProxyBackend();
  static const key =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  Future<ProcessResult> _run(List<String> args) =>
      Process.run('reg.exe', args, runInShell: false)
          .timeout(const Duration(seconds: 6));

  Future<String?> _query(String name) async {
    final result = await _run(['query', key, '/v', name]);
    if (result.exitCode != 0) return null;
    final pattern = RegExp(
      r'^\s*' + RegExp.escape(name) + r'\s+REG_\w+\s+(.*)$',
      multiLine: true, caseSensitive: false,
    );
    return pattern.firstMatch(result.stdout.toString())?.group(1)?.trim();
  }

  @override
  Future<VelaProxySnapshot> read() async {
    final raw = await _query('ProxyEnable');
    final server = await _query('ProxyServer');
    final number = raw == null ? null : raw.startsWith('0x')
        ? int.tryParse(raw.substring(2), radix: 16) : int.tryParse(raw);
    return VelaProxySnapshot(enabled: number, server: server);
  }

  @override
  Future<bool> hasPac() async {
    final pac = await _query('AutoConfigURL');
    return pac != null && pac.isNotEmpty;
  }

  Future<void> _set(String name, String? value, String type) async {
    final args = value == null
        ? ['delete', key, '/v', name, '/f']
        : ['add', key, '/v', name, '/t', type, '/d', value, '/f'];
    final result = await _run(args);
    // Removing an absent registry value is harmless.
    if (result.exitCode != 0 && value != null) {
      throw StateError('Cannot update WinINet settings');
    }
  }

  @override
  Future<void> write(VelaProxySnapshot snapshot) async {
    // Always write endpoint first, then enable/disable.
    await _set('ProxyServer', snapshot.server, 'REG_SZ');
    await _set('ProxyEnable', snapshot.enabled?.toString(), 'REG_DWORD');
  }

  @override
  Future<void> refresh() async {
    const script = r'''
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VelaWinInet {
 [DllImport("wininet.dll", SetLastError=true)]
 public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);
}
'@
[VelaWinInet]::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0) | Out-Null
[VelaWinInet]::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0) | Out-Null
''';
    final result = await Process.run('powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false).timeout(const Duration(seconds: 9));
    if (result.exitCode != 0) throw StateError('WinINet refresh failed');
  }
}

/// Never overwrite settings subsequently changed by a user/other application.
/// The on-disk restore journal is written BEFORE WinINet is modified.
class VelaSystemProxyManager extends ChangeNotifier {
  VelaSystemProxyManager({
    VelaWindowsProxyBackend? backend,
    Directory? stateDirectory,
    bool? supported,
  }) : _backend = backend ?? const VelaRegistryProxyBackend(),
       _directory = stateDirectory ?? _defaultDirectory(),
       supported = supported ?? Platform.isWindows;

  static Directory? _defaultDirectory() {
    if (!Platform.isWindows) return null;
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.isEmpty) return null;
    return Directory(root + Platform.pathSeparator + 'Vela-SHUO' +
        Platform.pathSeparator + 'State');
  }

  static const managed = VelaProxySnapshot(
    enabled: 1, server: '127.0.0.1:20808',
  );
  final VelaWindowsProxyBackend _backend;
  final Directory? _directory;
  final bool supported;
  bool _busy = false;
  bool _active = false;
  String? _error;
  bool get busy => _busy;
  bool get active => _active;
  String? get error => _error;
  File? get _journal => _directory == null ? null :
      File(_directory.path + Platform.pathSeparator + 'proxy-recovery.json');

  Future<void> _save(VelaProxySnapshot previous) async {
    final journal = _journal;
    if (journal == null) throw StateError('Recovery path missing');
    await journal.parent.create(recursive: true);
    if (await journal.exists()) throw StateError('Pending recovery');
    final temp = File(journal.path + '.tmp');
    await temp.writeAsString(jsonEncode({
      'schema': 1, 'managed': managed.toJson(),
      'previous': previous.toJson(),
    }), flush: true);
    await temp.rename(journal.path);
  }

  Future<VelaProxySnapshot?> _previous() async {
    final journal = _journal;
    if (journal == null || !await journal.exists()) return null;
    if (await journal.length() > 4096) throw StateError('Invalid journal');
    final obj = jsonDecode(await journal.readAsString());
    if (obj is! Map<String, dynamic> || obj['schema'] != 1 ||
        obj['managed'] is! Map<String, dynamic> ||
        obj['previous'] is! Map<String, dynamic> ||
        !VelaProxySnapshot.fromJson(obj['managed']).equals(managed)) {
      throw StateError('Invalid recovery state');
    }
    return VelaProxySnapshot.fromJson(obj['previous']);
  }

  Future<void> _clear() async {
    final file = _journal;
    if (file != null && await file.exists()) await file.delete();
  }

  void _notify([String? error]) {
    _error = error;
    notifyListeners();
  }

  /// On startup, recover only our exact prior proxy setting, never a
  /// different proxy that another app installed after a crash.
  Future<bool> recover() async {
    if (!supported || _busy) return !supported;
    _busy = true;
    _notify();
    try {
      final old = await _previous();
      if (old == null) return true;
      final current = await _backend.read();
      if (current.equals(managed)) {
        await _backend.write(old);
        await _backend.refresh();
        if (!(await _backend.read()).equals(old)) {
          throw StateError('Restore not verified');
        }
      } else if (!current.equals(old)) {
        await _clear();
        _notify('检测到其他程序已改动代理设置，未覆盖它');
        return true;
      }
      await _clear();
      _active = false;
      return true;
    } catch (_) {
      _notify('上次系统代理设置未能恢复，请先检查 Windows 代理设置');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> enable() async {
    if (!supported || _busy) return false;
    if (_active) return true;
    _busy = true;
    _notify();
    try {
      if (await _previous() != null) throw StateError('Pending recovery');
      if (await _backend.hasPac()) {
        _notify('检测到 PAC 自动代理脚本，为保护原设置，暂不接管');
        return false;
      }
      final original = await _backend.read();
      await _save(original);
      await _backend.write(managed);
      await _backend.refresh();
      if (!(await _backend.read()).equals(managed)) {
        throw StateError('Proxy apply not verified');
      }
      _active = true;
      return true;
    } catch (_) {
      try {
        final old = await _previous();
        if (old != null) {
          await _backend.write(old);
          await _backend.refresh();
          if ((await _backend.read()).equals(old)) await _clear();
        }
      } catch (_) {}
      _notify('系统代理接管失败，已尝试回滚；请检查 Windows 代理设置');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> disable() async {
    if (!supported || _busy) return false;
    _busy = true;
    _notify();
    try {
      final old = await _previous();
      if (old == null) {
        _active = false;
        return true;
      }
      final current = await _backend.read();
      if (!current.equals(managed)) {
        await _clear();
        _active = false;
        _notify('其他程序已接管系统代理，未覆盖其配置');
        return true;
      }
      await _backend.write(old);
      await _backend.refresh();
      if (!(await _backend.read()).equals(old)) {
        throw StateError('Restore not verified');
      }
      await _clear();
      _active = false;
      return true;
    } catch (_) {
      _notify('系统代理恢复失败；为避免断网，暂不关闭内核');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
