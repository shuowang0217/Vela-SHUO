import 'dart:async';
import 'dart:io';

/// Only trust localhost HTTP proxies from Windows internet settings.
/// No proxy credentials or remotely configured proxy endpoints are accepted.
class VelaWindowsProxyDetector {
  const VelaWindowsProxyDetector();

  static const String registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  static String? parseRegistryOutput(
      String enabledOutput, String serverOutput) {
    if (!RegExp(r'ProxyEnable\s+REG_DWORD\s+0x0*1\b',
        caseSensitive: false).hasMatch(enabledOutput)) {
      return null;
    }
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+([^\r\n]+)',
        caseSensitive: false).firstMatch(serverOutput);
    if (match == null) return null;
    return parseProxyServer(match.group(1)!.trim());
  }

  static String? parseProxyServer(String config) {
    if (config.isEmpty || config.contains('@')) return null;
    final assignments = <String, String>{};
    for (final part in config.split(';')) {
      final entry = part.trim();
      final index = entry.indexOf('=');
      if (index >= 0) {
        assignments[entry.substring(0, index).trim().toLowerCase()] =
            entry.substring(index + 1).trim();
      } else if (entry.isNotEmpty) {
        assignments.putIfAbsent('default', () => entry);
      }
    }
    final raw = assignments['https'] ??
        assignments['http'] ?? assignments['default'];
    if (raw == null || raw.isEmpty) return null;
    final endpoint = raw.toLowerCase().startsWith('http://')
        ? raw.substring(7) : raw;
    final match = RegExp(r'^(127\.0\.0\.1|localhost|\[::1\]):(\d{1,5})$',
      caseSensitive: false).firstMatch(endpoint);
    if (match == null) return null;
    final port = int.tryParse(match.group(2)!);
    if (port == null || port < 1 || port > 65535 || port == 20808) {
      // Avoid recursively connecting to Vela's own local listener.
      return null;
    }
    final host = match.group(1)!.toLowerCase() == 'localhost'
        ? '127.0.0.1' : match.group(1)!;
    return 'PROXY $host:$port';
  }

  Future<String?> detect() async {
    if (!Platform.isWindows) return null;
    try {
      final queries = await Future.wait([
        Process.run('reg.exe', ['query', registryKey, '/v', 'ProxyEnable'],
            runInShell: false),
        Process.run('reg.exe', ['query', registryKey, '/v', 'ProxyServer'],
            runInShell: false),
      ]).timeout(const Duration(seconds: 4));
      if (queries.every((r) => r.exitCode == 0)) {
        final detected = parseRegistryOutput(queries[0].stdout.toString(),
            queries[1].stdout.toString());
        if (detected != null) {
          return detected;
        }
      }
      return _environmentProxy();
    } catch (_) {
      // Registry restrictions must not prevent use of a safe loopback HTTP
      // proxy explicitly configured in the current process environment.
      return _environmentProxy();
    }
  }

  static String? _environmentProxy() {
    for (final key in ['HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY',
        'http_proxy']) {
      final value = Platform.environment[key];
      if (value == null) {
        continue;
      }
      final proxy = parseProxyServer(value);
      if (proxy != null) {
        return proxy;
      }
    }
    return null;
  }
}
