import 'dart:convert';
import 'dart:io';

/// Vela stable releases are published only after Android/Windows CI passes.
/// The app never silently downloads or installs executable code.
class VelaUpdateInfo {
  const VelaUpdateInfo({
    required this.latestVersion,
    required this.available,
    required this.assetUrl,
  });

  final String latestVersion;
  final bool available;
  final Uri? assetUrl;
}

class VelaUpdateService {
  const VelaUpdateService();

  static const String currentVersion = '1.8.10';
  static final Uri _releaseApi = Uri.https(
      'api.github.com', '/repos/shuowang0217/Vela-SHUO/releases/latest');

  static bool isNewer(String candidate, String installed) {
    List<int>? parts(String version) {
      final cleaned = version.startsWith('v') ? version.substring(1) : version;
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(cleaned)) return null;
      return cleaned.split('.').map(int.parse).toList();
    }

    final next = parts(candidate);
    final now = parts(installed);
    if (next == null || now == null) return false;
    for (var i = 0; i < 3; i++) {
      if (next[i] != now[i]) return next[i] > now[i];
    }
    return false;
  }

  Future<VelaUpdateInfo> check() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(_releaseApi)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, 'Vela/$currentVersion');
      request.headers.set(HttpHeaders.acceptHeader,
          'application/vnd.github+json');
      final response = await request.close().timeout(
          const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException('Release endpoint unavailable');
      }
      final body = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(body);
      if (json is! Map || json['tag_name'] is! String ||
          json['assets'] is! List) {
        throw const FormatException('Invalid release metadata');
      }
      final version = json['tag_name'] as String;
      final available = isNewer(version, currentVersion);
      if (!available) {
        return VelaUpdateInfo(
            latestVersion: version, available: false, assetUrl: null);
      }

      final suffix = Platform.isAndroid
          ? '-Android-arm64.apk' : '-Windows-x64.zip';
      Uri? target;
      for (final item in json['assets'] as List) {
        if (item is! Map || item['name'] is! String ||
            item['browser_download_url'] is! String ||
            !(item['name'] as String).endsWith(suffix)) {
          continue;
        }
        final url = Uri.tryParse(item['browser_download_url'] as String);
        if (url != null && url.scheme == 'https' &&
            url.host == 'github.com' &&
            url.path.startsWith('/shuowang0217/Vela-SHUO/releases/download/')) {
          target = url;
          break;
        }
      }
      if (target == null) {
        throw const FormatException('No matching release package');
      }
      return VelaUpdateInfo(
          latestVersion: version, available: true, assetUrl: target);
    } finally {
      client.close(force: true);
    }
  }
}
