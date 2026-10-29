import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'flclash_core_api.dart';

/// IP detection uses the SAME FlClash Go/Mihomo outboundIp RPC on both
/// platforms. The core chooses the real route (including RULE/DIRECT); a
/// node name is never used to guess IP geolocation.
class VelaExitIpInfo {
  const VelaExitIpInfo({
    required this.address,
    required this.countryCode,
    this.chains = const [],
    this.coreEpoch,
    this.picksVersion,
    this.source,
  });

  final String address;
  final String countryCode;
  /// Actual core route chain, not the geographic city inferred from a name.
  final List<String> chains;
  final int? coreEpoch;
  final int? picksVersion;
  final String? source;

  bool get routeVerified =>
      chains.isNotEmpty && coreEpoch != null && picksVersion != null;

  VelaExitIpInfo withNativeRoute(Map<String, dynamic> result) {
    final raw = result['chains'];
    final chain = raw is List
        ? raw.whereType<String>().where((s) => s.isNotEmpty).toList()
        : <String>[];
    return VelaExitIpInfo(
      address: address,
      countryCode: countryCode,
      chains: List<String>.unmodifiable(chain),
      coreEpoch: result['core-epoch'] is int
          ? result['core-epoch'] as int : null,
      picksVersion: result['picks-version'] is int
          ? result['picks-version'] as int : null,
      source: result['url'] is String ? result['url'] as String : null,
    );
  }

  String get flag => String.fromCharCodes([
    127397 + countryCode.codeUnitAt(0),
    127397 + countryCode.codeUnitAt(1),
  ]);

  String get label => '$flag $address';

  /// Parse only a known provider's expected fields, never a random 200 page.
  /// Source formats mirror FlClash's lib/common/service_probe.dart.
  static VelaExitIpInfo? parseSource(String url, String body) {
    if (body.isEmpty || body.length > 4096) {
      return null;
    }
    String? ip;
    String? country;
    try {
      if (url == VelaExitIpProbe.cloudflare) {
        final fields = <String, String>{};
        for (final line in const LineSplitter().convert(body)) {
          final separator = line.indexOf('=');
          if (separator > 0) {
            fields[line.substring(0, separator)] =
                line.substring(separator + 1).trim();
          }
        }
        ip = fields['ip'];
        country = fields['loc'];
      } else {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          return null;
        }
        if (url == VelaExitIpProbe.ipInfo ||
            url == VelaExitIpProbe.countryIs) {
          ip = decoded['ip'] as String?;
          country = decoded['country'] as String?;
        } else if (url == VelaExitIpProbe.ipSb ||
            url == VelaExitIpProbe.ipWhoIs ||
            url == VelaExitIpProbe.geoJs) {
          ip = decoded['ip'] as String?;
          country = decoded['country_code'] as String?;
        } else if (url == VelaExitIpProbe.identMe) {
          ip = decoded['ip'] as String?;
          country = decoded['cc'] as String?;
        } else if (url == VelaExitIpProbe.ipQuery) {
          ip = decoded['ip'] as String?;
          final location = decoded['location'];
          if (location is Map) {
            country = location['country_code'] as String?;
          }
        } else {
          return null;
        }
      }
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    if (ip == null || country == null ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(country) ||
        country == 'ZZ') {
      return null;
    }
    final address = InternetAddress.tryParse(ip);
    if (address == null || address.isLoopback ||
        address.isLinkLocal || address.isMulticast) {
      return null;
    }
    if (address.type == InternetAddressType.IPv4) {
      final bytes = address.rawAddress;
      if (bytes[0] == 0 || bytes[0] == 10 ||
          (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168)) {
        return null;
      }
    } else if (address.type == InternetAddressType.IPv6) {
      if ((address.rawAddress[0] & 0xfe) == 0xfc) {
        return null;
      }
    } else {
      return null;
    }
    return VelaExitIpInfo(address: ip, countryCode: country);
  }
}

/// FlClash Go's native outboundIp engine performs staggered probes (up to
/// three concurrent, 800ms apart), using Mihomo's tunnel and route chain.
/// All sources are HTTPS; the upstream Custom fork also offers an HTTP-only
/// endpoint which is intentionally omitted for this sensitive IP lookup.
class VelaExitIpProbe {
  VelaExitIpProbe(this.api);

  final FlClashCoreApi api;
  int _generation = 0;
  String? lastFailure;

  static const cloudflare = 'https://www.cloudflare.com/cdn-cgi/trace';
  static const ipSb = 'https://api.ip.sb/geoip';
  static const ipInfo = 'https://ipinfo.io/json';
  static const ipWhoIs = 'https://ipwho.is';
  static const geoJs = 'https://get.geojs.io/v1/ip/geo.json';
  static const countryIs = 'https://api.country.is';
  static const ipQuery = 'https://api.ipquery.io/?format=json';
  static const identMe = 'https://ident.me/json';

  static const sources = <String>[
    cloudflare, ipSb, ipInfo, ipWhoIs,
    geoJs, countryIs, ipQuery, identMe,
  ];

  Future<VelaExitIpInfo?> lookup() async {
    lastFailure = null;
    final generation = _generation;
    var urls = sources;
    // The Go core accepts the first body containing a public IP. If that
    // particular provider omits a valid country, exclude it for one retry.
    for (var attempt = 0; attempt < 2; attempt++) {
      if (generation != _generation || urls.isEmpty) {
        return null;
      }
      try {
        final reply = await api.outboundIp(urls: urls, timeoutMs: 6000);
        if (generation != _generation) {
          return null;
        }
        if (reply == null) {
          lastFailure = '内核未返回检测结果';
          return null;
        }
        if (reply['error'] is String && (reply['error'] as String).isNotEmpty) {
          lastFailure = reply['error'] == 'timeout'
              ? '出口检测超时' : '检测服务无有效响应';
          return null;
        }
        final url = reply['url'];
        final body = reply['body'];
        if (url is! String || body is! String) {
          lastFailure = '原生检测结果格式异常';
          return null;
        }
        final info = VelaExitIpInfo.parseSource(url, body);
        if (info != null) {
          return info.withNativeRoute(reply);
        }
        lastFailure = '检测网站没有返回有效 IP 与国家';

        if (!urls.contains(url)) {
          return null;
        }
        urls = urls.where((source) => source != url).toList(growable: false);
      } on TimeoutException {
        lastFailure = '原生内核检测超时';
        return null;
      } catch (_) {
        // Deliberately never expose native error text or a subscription URL.
        lastFailure = '内核检测调用失败';
        return null;
      }
    }
    lastFailure ??= '未获得有效出口 IP';
    return null;
  }

  /// Only invalidates Dart responses. The Go handler owns its 6s deadline.
  void cancel() => _generation++;
}

/// One verified result per active route. Core/VPN initialization may finish
/// shortly after "connected", so initial probe failures retry automatically.
/// Focus changes never clear the displayed IP.
class VelaExitIpMonitor extends ChangeNotifier {
  VelaExitIpMonitor({
    required VelaExitIpProbe probe,
    Duration interval = const Duration(minutes: 2),
    Duration maxAge = const Duration(minutes: 6),
    DateTime Function()? clock,
    Duration connectionSettle = const Duration(milliseconds: 700),
    List<Duration> initialRetries = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
  }) : _probe = probe,
       _interval = interval,
       _maxAge = maxAge,
       _clock = clock ?? DateTime.now,
       _connectionSettle = connectionSettle,
       _initialRetries = initialRetries;

  final VelaExitIpProbe _probe;
  final Duration _interval;
  final Duration _maxAge;
  final DateTime Function() _clock;
  final Duration _connectionSettle;
  final List<Duration> _initialRetries;

  Timer? _timer;
  Timer? _retryTimer;
  Timer? _expiryTimer;
  bool _connected = false;
  bool _loading = false;
  bool _disposed = false;
  String? _route;
  int _generation = 0;
  int _retryIndex = 0;
  VelaExitIpInfo? _info;
  DateTime? _verifiedAt;
  String? _failure;
  bool _lastCheckFailed = false;
  String _routeMode = 'rule';

  DateTime? get verifiedAt => _verifiedAt;
  String? get failureReason => _failure;
  bool get lastCheckFailed => _lastCheckFailed;
  String get routeMode => _routeMode;
  String get detectedChain => _info?.chains.join(' → ') ?? '';
  String get routeValidation => _info == null
      ? '无有效路由结果'
      : _info!.routeVerified ? '已获得内核真实路由链' : '内核未提供可核验的路由链';
  bool get hasExpired => _info == null && _failure == '上次检测结果已过期';

  bool get connected => _connected;
  bool get loading => _loading;
  VelaExitIpInfo? get info => _info;
  String get label => _info?.label ?? (_loading ? '检测中…' : 'timeout');

  void sync(bool connected, String routeIdentity, {
    String mode = 'rule',
  }) {
    if (_disposed || (_connected == connected &&
        (!connected || _route == routeIdentity))) {
      return;
    }
    _generation++;
    _connected = connected;
    _route = connected ? routeIdentity : null;
    _routeMode = mode;
    _probe.cancel();
    _timer?.cancel();
    _retryTimer?.cancel();
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _timer = null;
    _retryTimer = null;
    _retryIndex = 0;
    _loading = false;
    _info = null;
    _verifiedAt = null;
    _failure = null;
    _lastCheckFailed = false;
    notifyListeners();
    if (!connected) {
      return;
    }

    // Native Mihomo setup can be slightly behind the connected callback.
    // Automatic retry makes detection independent of focus changes.
    if (_connectionSettle == Duration.zero) {
      unawaited(refresh());
    } else {
      _loading = true;
      notifyListeners();
      _retryTimer = Timer(_connectionSettle, () {
        _retryTimer = null;
        _loading = false;
        unawaited(refresh());
      });
    }
    _timer = Timer.periodic(_interval, (_) => unawaited(refresh()));
  }

  Future<void> refresh() async {
    if (_disposed || !_connected || _loading) {
      return;
    }
    final generation = _generation;
    _loading = true;
    // A successful result remains visible during refresh on the same route.
    notifyListeners();
    try {
      final result = await _probe.lookup();
      if (!_disposed && _connected && generation == _generation) {
        if (result != null && _matchesMode(result)) {
          _info = result;
          _verifiedAt = _clock();
          _failure = null;
          _lastCheckFailed = false;
          _retryIndex = 0;
          _retryTimer?.cancel();
          _retryTimer = null;
          _expiryTimer?.cancel();
          _expiryTimer = Timer(_maxAge, () => _expire(generation));
        } else {
          _lastCheckFailed = true;
          _failure = result != null
              ? '实际出口与当前代理模式不一致'
              : (_probe.lastFailure ?? '出口检测失败');
          if (_info == null) {
            _scheduleRetry(generation);
          }
        }
      }
    } catch (_) {
      if (!_disposed && _connected && generation == _generation &&
          _info == null) {
        _failure = _probe.lastFailure ?? '出口检测失败';
        _lastCheckFailed = true;
        _scheduleRetry(generation);
      }
    } finally {
      if (!_disposed && _connected && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Long background suspension can outlive Dart timers; revalidate on
  /// resume, without disturbing short window-focus changes.
  Future<void> recheckAfterWake() async {
    if (_disposed || !_connected) return;
    final verified = _verifiedAt;
    if (verified != null &&
        _clock().difference(verified) >= _maxAge) {
      _expiryTimer?.cancel();
      _info = null;
      _verifiedAt = null;
      _failure = '上次检测结果已过期';
      _lastCheckFailed = true;
      notifyListeners();
    }
    await refresh();
  }

  bool _matchesMode(VelaExitIpInfo result) {
    // In RULE mode a DIRECT result can be perfectly legitimate: show its
    // actual chain in diagnostics instead of pretending it is a selected node.
    if (!result.routeVerified) {
      return true; // Older core responses remain usable but are marked unverified.
    }
    final direct = result.chains.contains('DIRECT');
    if (_routeMode == 'direct') return direct;
    if (_routeMode == 'global') return !direct;
    return true;
  }

  void _expire(int generation) {
    if (_disposed || !_connected || generation != _generation ||
        _info == null || _verifiedAt == null) {
      return;
    }
    if (_clock().difference(_verifiedAt!) < _maxAge) {
      _expiryTimer = Timer(
        _maxAge - _clock().difference(_verifiedAt!),
        () => _expire(generation),
      );
      return;
    }
    // A failed or stalled refresh must never preserve the old IP forever.
    _info = null;
    _verifiedAt = null;
    _failure = '上次检测结果已过期';
    _lastCheckFailed = true;
    notifyListeners();
    if (!_loading) _scheduleRetry(generation);
  }

  void _scheduleRetry(int generation) {
    if (_retryIndex >= _initialRetries.length || _retryTimer != null) {
      return;
    }
    final delay = _initialRetries[_retryIndex++];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_disposed && _connected && _generation == generation &&
          _info == null) {
        unawaited(refresh());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _retryTimer?.cancel();
    _expiryTimer?.cancel();
    _probe.cancel();
    super.dispose();
  }
}
