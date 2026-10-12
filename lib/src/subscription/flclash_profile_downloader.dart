import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'vela_subscription_controller.dart';
import 'vela_subscription_parser.dart';
import 'vela_windows_proxy_detector.dart';

class FlClashProfileResponse {
  const FlClashProfileResponse(this.statusCode, this.body, {this.redirect});
  final int statusCode;
  final Uint8List body;
  final String? redirect;
}
typedef FlClashProfileRequest = Future<FlClashProfileResponse> Function(
    Uri uri, String route);

/// FlClash's Dio byte download and locally-routed HTTP proxy path.
/// This belongs to the backend; none of the original Vela widgets change.
class FlClashProfileDownloader implements VelaSubscriptionFetcher {
  const FlClashProfileDownloader({
    this.mode = VelaSubscriptionDownloadMode.automatic,
    this.localHttpProxyPort,
    this.proxyLookup,
    this.discoverProxy,
    this.requestStep,
    this.userAgent = 'Clash.Meta',
  });
  final VelaSubscriptionDownloadMode mode;
  final int? localHttpProxyPort;
  final Future<String?> Function()? proxyLookup;
  final Future<String?> Function()? discoverProxy;
  final FlClashProfileRequest? requestStep;
  final String userAgent;

  static bool _validTarget(Uri uri) {
    if (uri.scheme != 'https' || !uri.hasAuthority || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    return host != 'localhost' && !host.endsWith('.localhost') &&
        !host.endsWith('.local') && InternetAddress.tryParse(host) == null;
  }

  static bool _validProxy(String route) {
    final match = RegExp(r'^PROXY (127\.0\.0\.1|\[::1\]):(\d{1,5})$')
        .firstMatch(route);
    return match != null &&
        VelaWindowsProxyDetector.allowedPort(int.tryParse(match.group(2)!));
  }

  Future<List<String>> _routes() async {
    if (mode == VelaSubscriptionDownloadMode.direct) return const ['DIRECT'];
    if (mode == VelaSubscriptionDownloadMode.localHttp) {
      if (!VelaWindowsProxyDetector.allowedPort(localHttpProxyPort)) {
        throw const FormatException('本机 HTTP/Mixed 代理端口无效');
      }
      return ['PROXY 127.0.0.1:$localHttpProxyPort'];
    }
    final detector = const VelaWindowsProxyDetector();
    final proxy = await (proxyLookup?.call() ?? detector.detect());
    final routes = <String>[];
    if (proxy != null && _validProxy(proxy)) routes.add(proxy);
    if (mode == VelaSubscriptionDownloadMode.systemProxy) {
      if (routes.isEmpty) throw const FormatException('未检测到本机 HTTP 系统代理');
      return routes;
    }
    if (Platform.isWindows || discoverProxy != null) {
      final extra = await (discoverProxy?.call() ??
          detector.discoverLocalHttpProxy());
      if (extra != null && _validProxy(extra) && !routes.contains(extra)) {
        routes.add(extra);
      }
    }
    return [...routes, 'DIRECT'];
  }

  Future<FlClashProfileResponse> _fetch(Uri uri, String route) async {
    if (requestStep != null) return requestStep!(uri, route);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': userAgent},
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..userAgent = userAgent;
      client.findProxy = (_) => route;
      return client;
    });
    try {
      final response = await dio.get<Uint8List>(uri.toString(),
        options: Options(responseType: ResponseType.bytes,
          followRedirects: false, validateStatus: (_) => true,
          headers: {'Accept': '*/*'}));
      return FlClashProfileResponse(response.statusCode ?? 0,
          response.data ?? Uint8List(0),
          redirect: response.headers.value(HttpHeaders.locationHeader));
    } finally {
      dio.close(force: true);
    }
  }

  @override
  Future<String> download(String source) async {
    final start = Uri.tryParse(source.trim());
    if (start == null || !_validTarget(start)) {
      throw const FormatException('仅支持公网域名的 HTTPS 订阅链接');
    }
    var lastError = 'Dio 订阅请求失败，请检查本机代理或网络';
    for (final route in await _routes()) {
      try {
        var uri = start;
        final seen = <Uri>{};
        for (var n = 0; n <= 6; n++) {
          if (!seen.add(uri)) throw const FormatException('订阅链接循环跳转');
          final response = await _fetch(uri, route);
          if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
            final location = response.redirect;
            if (location == null || location.isEmpty) {
              throw const FormatException('订阅跳转地址缺失');
            }
            final next = uri.resolve(location);
            if (!_validTarget(next)) {
              throw const FormatException('订阅不允许跳转到非 HTTPS 或本机地址');
            }
            uri = next;
            continue;
          }
          if (response.statusCode != 200) {
            lastError = '订阅服务器返回 HTTP ' + response.statusCode.toString();
            break;
          }
          if (response.body.isEmpty ||
              response.body.length > VelaSubscriptionParser.maxBytes) {
            throw const FormatException('订阅为空或大小超过允许限制');
          }
          return utf8.decode(response.body);
        }
        if (seen.length > 6) throw const FormatException('订阅跳转次数过多');
      } on DioException {
        lastError = 'Dio 请求失败，请检查本机代理端口或网络';
      } on SocketException {
        lastError = '订阅网络连接失败';
      } on TimeoutException {
        lastError = '订阅连接超时';
      } on HandshakeException {
        lastError = 'HTTPS 证书验证失败';
      }
    }
    throw FormatException(lastError);
  }
}
