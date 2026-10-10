import 'dart:convert';
import 'dart:io';

/// Fixed loopback API. No external destination or Windows proxy fallback.
abstract class VelaMihomoSelectorApi {
  Future<String?> active(int port, String secret);
  Future<bool> select(int port, String secret, String node);
}

class VelaLoopbackMihomoSelectorApi implements VelaMihomoSelectorApi {
  const VelaLoopbackMihomoSelectorApi();

  static Uri _url(int port) {
    if (port < 1024 || port > 65535) {
      throw const FormatException('Mihomo 控制端口无效');
    }
    return Uri.parse('http://127.0.0.1:$port/proxies/VELA_SELECT');
  }

  @override
  Future<String?> active(int port, String secret) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(_url(port))
          .timeout(const Duration(seconds: 4));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      final response = await req.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != HttpStatus.ok || response.isRedirect ||
          response.contentLength > 8192) {
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 4))) {
        if (bytes.length + chunk.length > 8192) return null;
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map && decoded['now'] is String
          ? decoded['now'] as String : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> select(int port, String secret, String node) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    try {
      final req = await client.putUrl(_url(port))
          .timeout(const Duration(seconds: 4));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'name': node})));
      final response = await req.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      return !response.isRedirect &&
          (response.statusCode == HttpStatus.noContent ||
              response.statusCode == HttpStatus.ok);
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
