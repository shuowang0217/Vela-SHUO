import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'vela_subscription_controller.dart';
import 'vela_subscription_parser.dart';
import 'vela_windows_proxy_detector.dart';

/// Parsed from the response header that FlClash Profile.update() reads.
/// These are bytes and a Unix expiry time, NEVER the traffic of the device.
class FlClashSubscriptionUsage {
  const FlClashSubscriptionUsage({
    required this.upload, required this.download,
    required this.total, this.expire,
  });
  final int upload;
  final int download;
  final int total;
  final int? expire;

  int get used => upload + download;
  double get fraction => (used / total).clamp(0.0, 1.0).toDouble();

  /// FlClash receives "subscription-userinfo: upload=...; download=...;
  /// total=...; expire=..." from the subscription HTTP response.
  /// Reject malformed or incomplete values instead of showing false zeroes.
  static FlClashSubscriptionUsage? parse(String? header) {
    if (header == null || header.length > 2048) return null;
    final fields = <String, int>{};
    for (final segment in header.split(';')) {
      final pair = segment.trim().split('=');
      if (pair.length != 2) continue;
      final key = pair[0].trim().toLowerCase();
      if (!const {'upload', 'download', 'total', 'expire'}.contains(key)) {
        continue;
      }
      final value = int.tryParse(pair[1].trim());
      if (value != null && value >= 0) fields[key] = value;
    }
    final up = fields['upload'], down = fields['download'],
        total = fields['total'];
    if (up == null || down == null || total == null || total <= 0) {
      return null;
    }
    return FlClashSubscriptionUsage(upload: up, download: down,
        total: total, expire: fields['expire']);
  }
}

class FlClashProfileDownload {
  const FlClashProfileDownload(this.content, this.usage,
      {this.suggestedName});
  final String content;
  final FlClashSubscriptionUsage? usage;
  /// Origin-provided filename, same source used for FlClash's profile label.
  /// Null when the response did not supply trustworthy filename metadata.
  final String? suggestedName;
}

/// FlClash Profile.update() uses the final response's Content-Disposition
/// filename when the user left the profile label blank.
class VelaSubscriptionSuggestedName {
  const VelaSubscriptionSuggestedName._();

  /// The user-specified name always overrides the provider-supplied name.
  /// Empty/missing header metadata preserves the numbered local fallback.
  static String displayName(String? entered, String? provider, int ordinal) {
    final manual = (entered ?? '').trim();
    final supplied = (provider ?? '').trim();
    final name = manual.isNotEmpty ? manual
        : supplied.isNotEmpty ? supplied : '机场 $ordinal';
    return name.length > 64 ? name.substring(0, 64) : name;
  }

  static String? fromContentDisposition(String? header) {
    if (header == null || header.isEmpty || header.length > 2048) return null;
    try {
      final parsed = HeaderValue.parse(header);
      final params = parsed.parameters;
      String? candidate;
      final extended = params['filename*'];
      if (extended != null) {
        final parts = extended.split("''");
        if (parts.length >= 2 && parts.first.toLowerCase() == 'utf-8') {
          candidate = Uri.decodeComponent(parts.skip(1).join("''"));
        }
      }
      candidate ??= params['filename'];
      if (candidate == null) return null;
      final trimmed = candidate.trim();
      // Never treat a URL with query tokens, a local path, control
      // characters or separators as a displayable airport name.
      if (trimmed.isEmpty || trimmed.length > 64 ||
          RegExp(r'[\\/\r\n\x00-\x1f\x7f]').hasMatch(trimmed)) {
        return null;
      }
      return trimmed;
    } on FormatException {
      return null;
    }
  }
}

class FlClashProfileResponse {
  const FlClashProfileResponse(this.statusCode, this.body,
      {this.redirect, this.subscriptionUserInfo,
       this.contentDisposition});
  final int statusCode;
  final Uint8List body;
  final String? redirect;
  final String? subscriptionUserInfo;
  final String? contentDisposition;
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
        uri.userInfo.isNotEmpty) {
      return false;
    }
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
          redirect: response.headers.value(HttpHeaders.locationHeader),
          subscriptionUserInfo:
              response.headers.value('subscription-userinfo'),
          contentDisposition:
              response.headers.value('content-disposition'));
    } finally {
      dio.close(force: true);
    }
  }

  @override
  Future<String> download(String source) async =>
      (await downloadWithMetadata(source)).content;

  /// FlClash-style profile acquisition: return the exact Mihomo config
  /// bytes AND the subscription-userinfo metadata of the FINAL HTTP 200.
  Future<FlClashProfileDownload> downloadWithMetadata(String source) async {
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
            lastError = '订阅服务器返回 HTTP ${response.statusCode}';
            break;
          }
          if (response.body.isEmpty ||
              response.body.length > VelaSubscriptionParser.maxBytes) {
            throw const FormatException('订阅为空或大小超过允许限制');
          }
          return FlClashProfileDownload(
            utf8.decode(response.body),
            FlClashSubscriptionUsage.parse(response.subscriptionUserInfo),
            suggestedName: VelaSubscriptionSuggestedName.fromContentDisposition(
                response.contentDisposition),
          );
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
