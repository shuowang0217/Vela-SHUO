import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/vela_core_controller.dart';
import '../mihomo/vela_mihomo_config.dart';
import 'vela_subscription_parser.dart';
import 'vela_windows_proxy_detector.dart';

/// The subscription is fetched only after the user explicitly requests it.
/// Neither its URL (usually a bearer token) nor node credentials are logged
/// or stored in SharedPreferences.
abstract class VelaSubscriptionFetcher {
  Future<String> download(String source);
}

enum VelaSubscriptionDownloadMode { automatic, systemProxy, direct }

class _VelaSubscriptionTransportFailure implements Exception {
  const _VelaSubscriptionTransportFailure(this.reason);
  final String reason;
}

class VelaHttpsSubscriptionFetcher implements VelaSubscriptionFetcher {
  const VelaHttpsSubscriptionFetcher({
    this.mode = VelaSubscriptionDownloadMode.automatic,
    this.proxyLookup,
    this.fetchTransport,
    this.dnsCheck,
  });

  final VelaSubscriptionDownloadMode mode;
  final Future<String?> Function()? proxyLookup;
  final Future<String> Function(Uri, String)? fetchTransport;
  final Future<void> Function(String)? dnsCheck;

  static void _validateUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' || !uri.hasAuthority ||
        uri.userInfo.isNotEmpty || host.isEmpty ||
        host == 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local') || InternetAddress.tryParse(host) != null) {
      throw const FormatException('仅支持公网域名的 HTTPS 订阅链接');
    }
  }

  static Future<void> _checkDns(String host) async {
    final addresses = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 6));
    if (addresses.isEmpty) {
      throw const FormatException('订阅域名未解析到公网地址');
    }
    for (final ip in addresses) {
      if (ip.type == InternetAddressType.IPv6) {
        final bytes = ip.rawAddress;
        final allZeroPrefix = bytes.take(15).every((b) => b == 0);
        // Do not connect to loopback, ULA, link-local, multicast, or
        // IPv4-mapped addresses. Accept normal global unicast IPv6.
        if (bytes[0] == 0xff || // multicast
            (bytes[0] & 0xfe) == 0xfc || // unique-local
            (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
            allZeroPrefix ||
            (bytes.take(10).every((b) => b == 0) &&
                bytes[10] == 0xff && bytes[11] == 0xff)) {
          throw const FormatException('订阅域名包含非公网地址，已拒绝');
        }
        continue;
      }
      final bytes = ip.rawAddress;
      final a = bytes[0], b = bytes[1], c = bytes[2];
      if (a == 0 || a == 10 || a == 127 || a >= 224 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 192 && b == 0 && c == 0) ||
          (a == 198 && (b == 18 || b == 19))) {
        throw const FormatException('订阅域名包含非公网地址，已拒绝');
      }
    }
  }

  @override
  Future<String> download(String source) async {
    late final Uri uri;
    try {
      uri = Uri.parse(source.trim());
    } catch (_) {
      throw const FormatException('订阅地址格式不正确');
    }
    _validateUrl(uri);

    String? proxy;
    if (mode != VelaSubscriptionDownloadMode.direct) {
      proxy = proxyLookup == null
          ? await const VelaWindowsProxyDetector().detect()
          : await proxyLookup!();
      if (proxy != null &&
          !RegExp(r'^PROXY (127\.0\.0\.1|\[::1\]):\d{1,5}$')
              .hasMatch(proxy)) {
        proxy = null;
      }
    }
    if (mode == VelaSubscriptionDownloadMode.systemProxy &&
        proxy == null) {
      throw const FormatException(
        '未检测到本机 Windows HTTP 系统代理；请在现有代理软件中开启系统代理',
      );
    }
    // If a trusted localhost HTTP proxy is configured, let it resolve the
    // hostname. Clash/Mihomo Fake-IP DNS often returns 198.18.0.0/15, which
    // must not be mistaken for an actual subscription host. When using
    // DIRECT, all DNS answers must still be public.
    if (proxy == null) {
      try {
        if (dnsCheck != null) {
          await dnsCheck!(uri.host);
        } else {
          await _checkDns(uri.host);
        }
      } on SocketException {
        throw const FormatException('订阅域名无法解析，请检查 DNS 或使用系统代理');
      } on TimeoutException {
        throw const FormatException('订阅域名解析超时，请检查 DNS 或使用系统代理');
      }
    }

    final routes = <String>[
      ?proxy,
      if (mode != VelaSubscriptionDownloadMode.systemProxy) 'DIRECT',
    ];
    String? lastReason;
    for (final route in routes) {
      try {
        return await (fetchTransport == null
            ? _fetchVia(uri, route)
            : fetchTransport!(uri, route));
      } on _VelaSubscriptionTransportFailure catch (e) {
        lastReason = e.reason;
      } on TimeoutException {
        lastReason = '请求超时';
      } on SocketException {
        lastReason = '网络连接失败';
      } on HandshakeException {
        lastReason = 'HTTPS 证书验证失败';
      }
    }
    final hint = proxy != null && routes.length == 2
        ? '已尝试 Windows 本机系统代理和直连'
        : proxy != null ? '本机系统代理请求失败' : '直连请求失败';
    throw FormatException('$hint：${lastReason ?? '网络不可达'}');
  }

  Future<String> _fetchVia(Uri uri, String route) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.findProxy = (_) => route;
    // Ask providers for compatible Clash YAML without rewriting signed URLs.
    client.userAgent = 'Clash.Meta';
    try {
      final req = await client.getUrl(uri).timeout(
        const Duration(seconds: 12),
      );
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptHeader,
          'application/yaml, text/yaml, application/json, text/plain');
      final response = await req.close().timeout(
        const Duration(seconds: 14),
      );
      if (response.isRedirect) {
        throw const FormatException(
          '订阅地址返回重定向；出于凭据安全考虑不自动跳转，请使用最终 HTTPS 订阅链接',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException('订阅服务器返回 HTTP ${response.statusCode}');
      }
      final parts = <int>[];
      Future<void> receive() async {
        await for (final chunk in response.timeout(
          const Duration(seconds: 15),
        )) {
          if (parts.length + chunk.length >
              VelaSubscriptionParser.maxBytes) {
            throw const FormatException('订阅数据超过 2 MB 限制');
          }
          parts.addAll(chunk);
        }
      }
      await receive().timeout(const Duration(seconds: 35));
      try {
        return utf8.decode(parts, allowMalformed: false);
      } catch (_) {
        throw const FormatException('订阅不是 UTF-8 文本');
      }
    } on FormatException {
      rethrow;
    } on TimeoutException {
      throw const _VelaSubscriptionTransportFailure('连接或读取超时');
    } on HandshakeException {
      throw const _VelaSubscriptionTransportFailure('HTTPS 证书验证失败');
    } on SocketException {
      throw const _VelaSubscriptionTransportFailure('无法连接订阅服务器');
    } on HttpException {
      throw const _VelaSubscriptionTransportFailure('HTTP 连接异常');
    } catch (_) {
      throw const _VelaSubscriptionTransportFailure('订阅下载失败');
    } finally {
      client.close(force: true);
    }
  }
}

enum VelaSubscriptionPhase { idle, loading, ready, failed }

class VelaSubscriptionController extends ChangeNotifier {
  VelaSubscriptionController({
    VelaSubscriptionFetcher? fetcher,
    required this.core,
  }) : _fetcher = fetcher ?? const VelaHttpsSubscriptionFetcher();

  final VelaSubscriptionFetcher _fetcher;
  final VelaCoreController core;
  VelaSubscriptionPhase _phase = VelaSubscriptionPhase.idle;
  VelaSubscriptionResult? _result;
  VelaMihomoConfiguration? _preparedProfile;
  int? _selected;
  String? _error;
  bool _disposed = false;
  int _generation = 0;
  VelaSubscriptionDownloadMode _downloadMode =
      VelaSubscriptionDownloadMode.automatic;
  VelaSubscriptionDownloadMode get downloadMode => _downloadMode;

  void setDownloadMode(VelaSubscriptionDownloadMode next) {
    if (loading || core.busy || core.isListening) return;
    _downloadMode = next;
    _notify();
  }

  VelaSubscriptionPhase get phase => _phase;
  List<VelaSubscriptionNode> get nodes => _result?.nodes ?? const [];
  int get skipped => _result?.skipped ?? 0;
  String? get format => _result?.format;
  int? get selectedIndex => _selected;
  String? get error => _error;
  bool get loading => _phase == VelaSubscriptionPhase.loading;
  String? configuredNameFor(int index) => _preparedProfile?.nameFor(index);

  /// The coordinator calls this only after the live API confirms the
  /// selected node and the remote HTTPS probe passes.
  bool confirmRunningSelection(int index) {
    if (_disposed || !core.isListening ||
        _preparedProfile?.nameFor(index) == null) {
      return false;
    }
    _selected = index;
    _error = null;
    _notify();
    return true;
  }

  VelaSubscriptionNode? get selected => _selected == null ||
      _selected! < 0 || _selected! >= nodes.length
      ? null : nodes[_selected!];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> importFromUrl(String url) async {
    if (loading || core.busy || core.isListening) { return false; }
    _phase = VelaSubscriptionPhase.loading;
    _error = null;
    _result = null;
    _preparedProfile = null;
    _selected = null;
    final generation = ++_generation;
    _notify();
    try {
      final activeFetcher = _fetcher is VelaHttpsSubscriptionFetcher
          ? VelaHttpsSubscriptionFetcher(mode: _downloadMode)
          : _fetcher;
      final raw = await activeFetcher.download(url);
      final parsed = VelaSubscriptionParser.parse(raw);
      if (generation != _generation || _disposed) { return false; }
      _result = parsed;
      _phase = VelaSubscriptionPhase.ready;
      _notify();
      return true;
    } on FormatException catch (e) {
      if (generation != _generation || _disposed) { return false; }
      // Error text must only be authored by our parser/fetcher.
      _error = e.message;
    } catch (_) {
      if (generation != _generation || _disposed) { return false; }
      _error = '订阅导入失败，请检查格式或网络';
    }
    _phase = VelaSubscriptionPhase.failed;
    _notify();
    return false;
  }

  Future<bool> selectNode(int index) async {
    if (loading || core.busy || core.isListening ||
        index < 0 || index >= nodes.length) { return false; }
    // Whitelisted conversion: subscriptions cannot supply listeners or TUN.
    late final VelaMihomoConfiguration prepared;
    try {
      final random = Random.secure();
      final secret = List.generate(32, (_) =>
          random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      prepared = const VelaMihomoConfigBuilder().build(nodes,
        selectedIndex: index, secret: secret,
        proxyPort: 20808, apiPort: 20819,
      );
    } on FormatException {
      _error = '所选节点不兼容 Mihomo，请换一个节点';
      _notify();
      return false;
    }
    final ok = await core.useRemoteSubscriptionProfile(prepared.configText);
    if (ok) {
      _selected = index;
      _preparedProfile = prepared;
      _error = null;
    } else {
      _error = '无法准备节点配置，请检查磁盘权限';
    }
    _notify();
    return ok;
  }

  @override
  void dispose() {
    ++_generation;
    _result = null;
    _preparedProfile = null;
    _selected = null;
    _disposed = true;
    super.dispose();
  }
}
