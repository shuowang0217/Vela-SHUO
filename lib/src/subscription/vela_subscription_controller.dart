// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/vela_core_controller.dart';
import '../mihomo/vela_mihomo_config.dart';
import 'vela_subscription_parser.dart';
import 'vela_subscription_vault.dart';
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
    this.dnsLookup,
    this.secureDnsLookup,
  });

  final VelaSubscriptionDownloadMode mode;
  final Future<String?> Function()? proxyLookup;
  final Future<String> Function(Uri, String)? fetchTransport;
  final Future<void> Function(String)? dnsCheck;
  final Future<List<InternetAddress>> Function(String)? dnsLookup;

  /// DNS-over-HTTPS fallback (pinned public resolver IPs). Only consulted
  /// after local DNS fails or returns no acceptable public/Fake-IP targets.
  final Future<List<InternetAddress>> Function(String)? secureDnsLookup;

  static void _validateUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' || !uri.hasAuthority ||
        uri.userInfo.isNotEmpty || host.isEmpty ||
        host == 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local') || InternetAddress.tryParse(host) != null) {
      throw const FormatException('仅支持公网域名的 HTTPS 订阅链接');
    }
  }

  static bool isFakeIp(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) {
      return false;
    }
    final bytes = address.rawAddress;
    return bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19);
  }

  static bool isPublicIp(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv6) {
      if (bytes.length != 16) {
        return false;
      }
      // Global unicast only. Reject ULA, link-local, IPv4-mapped, etc.
      return (bytes[0] & 0xe0) == 0x20;
    }
    if (address.type != InternetAddressType.IPv4 ||
        bytes.length != 4) {
      return false;
    }
    final a = bytes[0], b = bytes[1], c = bytes[2];
    return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && (b == 0 || b == 168)) ||
        (a == 192 && b == 88 && c == 99) ||
        (a == 192 && b == 0 && c == 2) ||
        (a == 198 && (b == 18 || b == 19 ||
            (b == 51 && c == 100))) ||
        (a == 203 && b == 0 && c == 113));
  }

  /// Keep safe global addresses ahead of Mihomo's 198.18/15 Fake-IP.
  /// Mixed public/private results never authorize a private socket.
  static List<InternetAddress> checkedAddresses(
      List<InternetAddress> addresses) {
    final v4 = <InternetAddress>[], v6 = <InternetAddress>[];
    final fake = <InternetAddress>[], seen = <String>{};
    for (final ip in addresses) {
      if (!seen.add(ip.address)) {
        continue;
      }
      if (isPublicIp(ip)) {
        (ip.type == InternetAddressType.IPv4 ? v4 : v6).add(ip);
      } else if (isFakeIp(ip)) {
        fake.add(ip);
      }
    }
    final safe = <InternetAddress>[...v4, ...v6, ...fake];
    if (safe.isEmpty) {
      throw const FormatException(
          '订阅域名仅解析到内网或保留地址，已拒绝；可尝试本机 HTTP 系统代理');
    }
    return safe.take(8).toList(growable: false);
  }

  /// Queries a public DNS-over-HTTPS resolver WITHOUT resolving the DoH
  /// server through the local (possibly hijacked) DNS. HTTPS still validates
  /// the resolver certificate against its real hostname; socket IP is pinned.
  /// These fixed addresses are public, not derived from untrusted DNS.
  static Future<List<InternetAddress>> _lookupViaDoh(String host) async {
    const resolvers = <(String, String, String)>[
      // Alibaba's public JSON DoH service works on mainland networks.
      // The pinned address is public, with TLS verified for dns.alidns.com.
      ('dns.alidns.com', '223.5.5.5', '/resolve'),
      ('dns.alidns.com', '223.6.6.6', '/resolve'),
      ('cloudflare-dns.com', '1.1.1.1', '/dns-query'),
      ('dns.google', '8.8.8.8', '/resolve'),
    ];
    for (final (dnsHost, dnsIp, endpoint) in resolvers) {
      final results = <InternetAddress>[];
      var succeeded = false;
      for (final type in ['A', 'AAAA']) {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        client.findProxy = (_) => 'DIRECT';
        client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
          if (proxyHost != null || proxyPort != null ||
              uri.host != dnsHost || uri.scheme != 'https') {
            throw const FormatException('不允许 DNS 查询重定向');
          }
          return Socket.startConnect(InternetAddress(dnsIp), 443);
        };
        try {
          final uri = Uri.https(dnsHost, endpoint, <String, String>{
            'name': host,
            'type': type,
          });
          final request = await client.getUrl(uri)
              .timeout(const Duration(seconds: 6));
          request.followRedirects = false;
          request.headers.set(HttpHeaders.acceptHeader,
              'application/dns-json');
          final response = await request.close()
              .timeout(const Duration(seconds: 6));
          if (response.statusCode != HttpStatus.ok || response.isRedirect ||
              response.contentLength > 32768) {
            continue;
          }
          final bytes = <int>[];
          await for (final chunk in response.timeout(
              const Duration(seconds: 4))) {
            if (bytes.length + chunk.length > 32768) {
              break;
            }
            bytes.addAll(chunk);
          }
          if (bytes.isEmpty || bytes.length > 32768) {
            continue;
          }
          final result = jsonDecode(utf8.decode(bytes));
          if (result is! Map || result['Status'] != 0) {
            continue;
          }
          succeeded = true;
          final answers = result['Answer'];
          if (answers is! List) {
            continue;
          }
          for (final value in answers) {
            if (value is! Map || value['type'] != (type == 'A' ? 1 : 28) ||
                value['data'] is! String) {
              continue;
            }
            final parsed = InternetAddress.tryParse(value['data'] as String);
            if (parsed != null && isPublicIp(parsed)) results.add(parsed);
          }
        } catch (_) {
          // Never include the DoH URL or subscription host in diagnostics.
        } finally {
          client.close(force: true);
        }
        // The vast majority of subscription hosts have valid A records.
        // Avoid unnecessary secondary AAAA requests once one is found.
        if (results.isNotEmpty) {
          break;
        }
      }
      if (results.isNotEmpty) {
        return checkedAddresses(results);
      }
      if (succeeded) {
        // A valid public resolver answer with no public addresses means
        // fail closed. Trying another resolver remains permissible.
        continue;
      }
    }
    throw const FormatException(
      '本机 DNS 返回不可用地址，安全 DNS 备用解析也未成功；'
      '请检查网络或在 Windows 中开启可信的本机 HTTP 系统代理');
  }

  Future<List<InternetAddress>> _resolveDirect(String host) async {
    if (dnsCheck != null) {
      await dnsCheck!(host);
      if (fetchTransport != null && dnsLookup == null &&
          secureDnsLookup == null) {
        return []; // Legacy mocked transport does not create sockets.
      }
    }
    try {
      final addresses = await (dnsLookup?.call(host) ??
              InternetAddress.lookup(host))
          .timeout(const Duration(seconds: 6));
      if (addresses.isNotEmpty) {
        final safe = checkedAddresses(addresses);
        if (safe.isNotEmpty) {
          return safe;
        }
      }
    } on FormatException {
      // System DNS was poisoned/rewritten to a private or reserved address.
      // Public DoH is the next path; never try to connect to that LAN IP.
    } on SocketException {
      // A DNS failure can be recovered by pinned public DNS-over-HTTPS.
    } on TimeoutException {
      // Likewise for a blocked or nonresponsive system resolver.
    }

    return _resolveSecureDns(host);
  }

  Future<List<InternetAddress>> _resolveSecureDns(String host) async {
    final secure = await (secureDnsLookup?.call(host) ??
        _lookupViaDoh(host)).timeout(const Duration(seconds: 24),
        onTimeout: () => throw const FormatException(
            '备用安全 DNS 查询超时，请检查网络'));
    // Even a trusted resolver cannot authorize an internal target.
    return checkedAddresses(secure.where(isPublicIp).toList());
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
    // Proxy resolution belongs to the trusted loopback HTTP proxy, not to
    // system DNS (which may be Mihomo Fake-IP). For DIRECT, resolve once
    // and pin the socket IP to prevent a DNS-rebinding TOCTOU.
    final routes = <String>[
      ?proxy,
      if (mode != VelaSubscriptionDownloadMode.systemProxy) 'DIRECT',
    ];
    String? lastReason;
    for (final route in routes) {
      try {
        final addresses = route == 'DIRECT'
            ? await _resolveDirect(uri.host) : null;
        if (fetchTransport != null) {
          return await fetchTransport!(uri, route);
        }
        try {
          return await _fetchVia(uri, route, addresses);
        } on _VelaSubscriptionTransportFailure {
          // A system resolver may return a syntactically safe but stale
          // address (including unreachable Fake-IP). Retry once against
          // independently verified DoH, without relaxing HTTPS checks.
          if (route != 'DIRECT' || addresses == null) {
            rethrow;
          }
          final secure = await _resolveSecureDns(uri.host);
          final retried = secure.where(
              (ip) => !addresses.any((old) => old.address == ip.address))
              .toList();
          if (retried.isEmpty) {
            rethrow;
          }
          return await _fetchVia(uri, route, retried);
        }
      } on FormatException {
        rethrow;
      } on _VelaSubscriptionTransportFailure catch (e) {
        lastReason = e.reason;
      } on TimeoutException {
        lastReason = '请求超时';
      } on SocketException {
        lastReason = '域名解析或网络连接失败';
      } on HandshakeException {
        lastReason = 'HTTPS 证书验证失败';
      }
    }
    final hint = proxy != null && routes.length == 2
        ? '已尝试 Windows 本机系统代理和直连'
        : proxy != null ? '本机系统代理请求失败' : '直连请求失败';
    throw FormatException(hint + '：' + (lastReason ?? '网络不可达'));
  }

  Future<String> _fetchVia(
      Uri uri, String route, List<InternetAddress>? addresses) async {
    final targets = addresses == null
        ? <InternetAddress?>[null]
        : addresses.map<InternetAddress?>((ip) => ip).toList();
    _VelaSubscriptionTransportFailure? lastFailure;
    for (final target in targets) {
      try {
        return await _fetchViaAddress(uri, route, target);
      } on _VelaSubscriptionTransportFailure catch (e) {
        lastFailure = e;
      }
    }
    throw lastFailure ??
        const _VelaSubscriptionTransportFailure('无可用解析地址');
  }

  Future<String> _fetchViaAddress(
      Uri uri, String route, InternetAddress? pinnedAddress) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.findProxy = (_) => route;
    client.userAgent = 'Clash.Meta';
    if (pinnedAddress != null) {
      client.connectionFactory =
          (Uri target, String? proxyHost, int? proxyPort) {
        if (proxyHost != null || proxyPort != null) {
          throw StateError('直连禁止使用代理重定向');
        }
        // Original URI keeps HTTPS certificate validation and SNI intact.
        return Socket.startConnect(pinnedAddress, target.port);
      };
    }
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
        throw FormatException(
            '订阅服务器返回 HTTP ' + response.statusCode.toString());
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
    this.previewOnly = false,
    VelaSubscriptionVault? vault,
  }) : _vault = vault ?? VelaDeviceSubscriptionVault(),
       _fetcher = fetcher ?? const VelaHttpsSubscriptionFetcher();

  final VelaSubscriptionFetcher _fetcher;
  final VelaSubscriptionVault _vault;
  String? _source;
  // The last successful HTTPS URL is RAM-only. Never written to the vault,
  // settings, diagnostics or core profile; cleared at application shutdown.
  String? _sessionUrl;
  DateTime? _lastUpdatedAt;
  bool get hasSessionUrl => _sessionUrl != null;
  bool get canRefresh => _sessionUrl != null && !loading && !_vaultBusy;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  bool _stored = false;
  bool _vaultBusy = false;
  bool get storedOnDevice => _stored;
  bool get vaultBusy => _vaultBusy;
  /// Preview-only node browsing; never starts a proxy or VPN.
  final bool previewOnly;
  final VelaCoreController core;
  VelaSubscriptionPhase _phase = VelaSubscriptionPhase.idle;
  VelaSubscriptionResult? _result;
  VelaMihomoConfiguration? _preparedProfile;
  int? _selected;
  final Set<int> _favorites = <int>{};
  String? _error;
  bool _disposed = false;
  int _generation = 0;
  VelaSubscriptionDownloadMode _downloadMode =
      VelaSubscriptionDownloadMode.automatic;
  VelaSubscriptionDownloadMode get downloadMode => _downloadMode;

  void setDownloadMode(VelaSubscriptionDownloadMode next) {
    if (loading || core.busy || core.isListening) {
      return;
    }
    _downloadMode = next;
    _notify();
  }

  VelaSubscriptionPhase get phase => _phase;
  List<VelaSubscriptionNode> get nodes => _result?.nodes ?? const [];
  int get skipped => _result?.skipped ?? 0;
  String? get format => _result?.format;
  int? get selectedIndex => _selected;
  int get favoriteCount => _favorites.length;
  bool isFavorite(int index) => _favorites.contains(index);

  /// A favorite changes browsing order only. It never changes the selected
  /// proxy or starts network activity; persistence remains opt-in.
  bool toggleFavorite(int index) {
    if (_disposed || loading || index < 0 || index >= nodes.length) {
      return false;
    }
    if (!_favorites.add(index)) _favorites.remove(index);
    _notify();
    return true;
  }

  /// Preserve smart benchmark order within each favorite/nonfavorite group,
  /// retaining original subscription indices for safe node selection.
  List<int> visibleNodeIndices({
    String query = '',
    bool favoritesOnly = false,
    List<int>? order,
  }) {
    final normalized = query.trim().toLowerCase();
    final seen = <int>{};
    final ordered = <int>[];
    if (order != null) {
      for (final i in order) {
        if (i >= 0 && i < nodes.length && seen.add(i)) ordered.add(i);
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      if (seen.add(i)) ordered.add(i);
    }
    final pinned = <int>[];
    final other = <int>[];
    for (final i in ordered) {
      if (favoritesOnly && !_favorites.contains(i)) {
        continue;
      }
      final node = nodes[i];
      if (normalized.isNotEmpty &&
          !node.name.toLowerCase().contains(normalized) &&
          !node.protocol.toLowerCase().contains(normalized)) {
        continue;
      }
      (_favorites.contains(i) ? pinned : other).add(i);
    }
    return <int>[...pinned, ...other];
  }

  String? get error => _error;
  bool get loading => _phase == VelaSubscriptionPhase.loading;
  bool get canSave => _source != null && !loading && !_vaultBusy;
  String? configuredNameFor(int index) => _preparedProfile?.nameFor(index);

  /// Mihomo Android gets only an allowlisted, app-generated profile.
  /// VpnService sets up TUN: subscription data cannot enable custom TUN
  /// listeners, user-provided rules, or remote API control.
  String? get androidVpnProfile {
    if (!previewOnly || selected == null || _preparedProfile == null) {
      return null;
    }
    final profile = jsonDecode(_preparedProfile!.configText);
    if (profile is! Map<String, dynamic>) {
      return null;
    }
    profile.remove('external-controller');
    profile.remove('secret');
    profile['mixed-port'] = 0;
    profile['dns'] = <String, dynamic>{
      'enable': true,
      'ipv6': false,
      'enhanced-mode': 'fake-ip',
      'fake-ip-range': '198.18.0.1/16',
      'nameserver': <String>['1.1.1.1', '8.8.8.8'],
      'default-nameserver': <String>['1.1.1.1', '8.8.8.8'],
    };
    return jsonEncode(profile);
  }


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

  /// A retry is always user initiated and uses only the in-memory last URL.
  /// Failed updates keep the existing node list and encrypted snapshot.
  Future<bool> refreshLastUrl() async {
    final url = _sessionUrl;
    if (url == null || _disposed || !canRefresh) {
      return false;
    }
    return importFromUrl(url);
  }

  static String _nodeIdentity(VelaSubscriptionNode node) =>
      node.name + '\u001f' + node.protocol + '\u001f' + node.server;

  /// Parses pasted share links or YAML without network, disk or settings I/O.
  Future<bool> importFromText(String source) async {
    if (loading || core.busy || core.isListening || _disposed) {
      return false;
    }
    _phase = VelaSubscriptionPhase.loading;
    _error = null;
    final generation = ++_generation;
    _notify();
    try {
      final parsed = VelaSubscriptionParser.parse(source);
      if (generation != _generation || _disposed) {
      return false;
    }
      // Only a complete parse can replace a previously usable subscription.
      _result = parsed;
      _preparedProfile = null;
      _selected = null;
      _favorites.clear();
      _source = source;
      _sessionUrl = null;
      _lastUpdatedAt = DateTime.now();
      _stored = false;
      _phase = VelaSubscriptionPhase.ready;
      _notify();
      return true;
    } on FormatException catch (e) {
      if (generation != _generation || _disposed) {
        return false;
      }
      _error = e.message;
    } catch (_) {
      if (generation != _generation || _disposed) {
        return false;
      }
      _error = '节点内容无效，请检查格式';
    }
    // Old nodes and favorites survive a malformed replacement.
    _phase = _result == null
        ? VelaSubscriptionPhase.failed : VelaSubscriptionPhase.ready;
    _notify();
    return false;
  }

  Future<bool> importFromUrl(String url) async {
    if (loading || core.busy || core.isListening || _disposed) {
      return false;
    }
    final normalizedUrl = url.trim();
    final sameSource = _sessionUrl != null &&
        _sessionUrl == normalizedUrl && _result != null;
    final previousNodes = nodes;
    final oldSelected = selected;
    final previousFavorites = <String>{
      for (final i in _favorites)
        if (i >= 0 && i < previousNodes.length)
          _nodeIdentity(previousNodes[i]),
    };

    _phase = VelaSubscriptionPhase.loading;
    _error = null;
    final generation = ++_generation;
    _notify();
    try {
      final activeFetcher = _fetcher is VelaHttpsSubscriptionFetcher
          ? VelaHttpsSubscriptionFetcher(mode: previewOnly
              ? VelaSubscriptionDownloadMode.direct : _downloadMode)
          : _fetcher;
      final raw = await activeFetcher.download(normalizedUrl);
      final parsed = VelaSubscriptionParser.parse(raw);
      if (generation != _generation || _disposed) {
        return false;
      }

      // Commit the new subscription only after both HTTPS fetch and parse.
      _result = parsed;
      _preparedProfile = null;
      _selected = null;
      _favorites.clear();
      if (sameSource) {
        for (var i = 0; i < parsed.nodes.length; i++) {
          if (previousFavorites.contains(_nodeIdentity(parsed.nodes[i]))) {
            _favorites.add(i);
          }
        }
      }
      _source = raw;
      _sessionUrl = normalizedUrl;
      _lastUpdatedAt = DateTime.now();
      _stored = false; // Explicit save is required to persist new credentials.
      _phase = VelaSubscriptionPhase.ready;
      _notify();

      // Rebuild the local prepared config for the same named endpoint only.
      // No Mihomo process, system proxy or Android VPN is started here.
      if (sameSource && oldSelected != null) {
        final identity = _nodeIdentity(oldSelected);
        final index = parsed.nodes.indexWhere(
            (node) => _nodeIdentity(node) == identity);
        if (index >= 0) await selectNode(index);
      }
      return true;
    } on FormatException catch (e) {
      if (generation != _generation || _disposed) {
        return false;
      }
      _error = e.message;
    } catch (_) {
      if (generation != _generation || _disposed) {
        return false;
      }
      _error = '订阅导入失败，请检查格式或网络';
    }
    // A temporary outage must not delete a working profile or favorites.
    _phase = _result == null
        ? VelaSubscriptionPhase.failed : VelaSubscriptionPhase.ready;
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
    // Android preview updates in-memory selection only. No native core,
    // listener, VPN service or Windows proxy state is ever changed.
    final ok = previewOnly ||
        await core.useRemoteSubscriptionProfile(prepared.configText);
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

  /// Loads an encrypted, explicitly saved snapshot; never fetches a URL,
  /// silently enables Windows proxy, or starts an Android VPN.
  Future<bool> restoreSaved() async {
    if (_disposed || loading || _vaultBusy ||
        core.busy || core.isListening || nodes.isNotEmpty) {
      return false;
    }
    _vaultBusy = true;
    _phase = VelaSubscriptionPhase.loading;
    final generation = ++_generation;
    _notify();
    try {
      final encoded = await _vault.read().timeout(const Duration(seconds: 6));
      if (_disposed || generation != _generation) {
        return false;
      }
      if (encoded == null) {
        _phase = VelaSubscriptionPhase.idle;
        return false;
      }
      // Up to 500 small favorite indices in the encrypted snapshot.
      if (utf8.encode(encoded).length > VelaSubscriptionParser.maxBytes + 4096) {
        throw const FormatException('存档过大');
      }
      final obj = jsonDecode(encoded);
      if (obj is! Map<String, dynamic> ||
          obj['v'] != 1 || obj['raw'] is! String) {
        throw const FormatException('存档版本或格式无效');
      }
      final raw = obj['raw'] as String;
      final parsed = VelaSubscriptionParser.parse(raw);
      if (_disposed || generation != _generation) {
        return false;
      }
      _source = raw;
      _sessionUrl = null;
      _lastUpdatedAt = null;
      _result = parsed;
      _selected = null;
      _favorites.clear();
      // Older v1 snapshots omit favorites. Bad entries cannot escape the
      // parsed node range and never invalidate an otherwise valid import.
      final savedFavorites = obj['favorites'];
      if (savedFavorites is List &&
          savedFavorites.length <= VelaSubscriptionParser.maxNodes) {
        for (final value in savedFavorites) {
          if (value is int && value >= 0 && value < parsed.nodes.length) {
            _favorites.add(value);
          }
        }
      }
      _phase = VelaSubscriptionPhase.ready;
      _stored = true;
      final index = obj['selected'];
      _notify();
      if (index is int && index >= 0 && index < nodes.length) {
        // Rebuild an ephemeral controller secret, but NEVER start the core.
        await selectNode(index);
      }
      return true;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _phase = VelaSubscriptionPhase.failed;
        _error = '加密订阅恢复失败，请重新导入或清除本机存档';
      }
      return false;
    } finally {
      _vaultBusy = false;
      _notify();
    }
  }

  /// Only called after a direct user action. Never write the subscription
  /// URL, only the validated source body and currently selected index.
  Future<bool> saveOnDevice() async {
    final source = _source;
    if (_disposed || _vaultBusy || loading || source == null) {
      return false;
    }
    _vaultBusy = true;
    _notify();
    try {
      final snapshot = jsonEncode(<String, dynamic>{
        'v': 1, 'raw': source, 'selected': _selected,
        'favorites': _favorites.toList()..sort(),
      });
      await _vault.write(snapshot).timeout(const Duration(seconds: 8));
      if (_disposed) {
        return false;
      }
      _stored = true;
      _error = null;
      return true;
    } catch (_) {
      _error = '本机安全存储不可用，订阅未保存；请检查系统权限';
      return false;
    } finally {
      _vaultBusy = false;
      _notify();
    }
  }

  /// Removes only Vela's own encrypted snapshot, not other applications'
  /// keys, current nodes, theme settings or Windows proxy recovery journal.
  Future<bool> clearSaved() async {
    if (_disposed || _vaultBusy || loading) {
      return false;
    }
    _vaultBusy = true;
    _notify();
    try {
      await _vault.delete().timeout(const Duration(seconds: 8));
      _stored = false;
      _error = null;
      return true;
    } catch (_) {
      _error = '删除本机订阅存档失败，请检查系统权限';
      return false;
    } finally {
      _vaultBusy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _result = null;
    _preparedProfile = null;
    _selected = null;
    _favorites.clear();
    _source = null;
    _sessionUrl = null;
    _lastUpdatedAt = null;
    _disposed = true;
    super.dispose();
  }
}
