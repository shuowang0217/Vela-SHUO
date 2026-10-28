import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'flclash_core_api.dart';

/// IP detection uses the SAME FlClash Go/Mihomo outboundIp RPC on both
/// platforms. The core chooses the real route (including RULE/DIRECT); a
/// node name is never used to guess IP geolocation.
class VelaExitIpInfo {
  const VelaExitIpInfo({required this.address, required this.countryCode});

  final String address;
  final String countryCode;

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
        if (generation != _generation || reply == null) {
          return null;
        }
        final url = reply['url'];
        final body = reply['body'];
        if (url is! String || body is! String) {
          return null;
        }
        final info = VelaExitIpInfo.parseSource(url, body);
        if (info != null) {
          return info;
        }
        if (!urls.contains(url)) {
          return null;
        }
        urls = urls.where((source) => source != url).toList(growable: false);
      } catch (_) {
        // Timeout, JNI/stdio failure or unavailable providers: UI is timeout.
        return null;
      }
    }
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
       _connectionSettle = connectionSettle,
       _initialRetries = initialRetries;

  final VelaExitIpProbe _probe;
  final Duration _interval;
  final Duration _connectionSettle;
  final List<Duration> _initialRetries;

  Timer? _timer;
  Timer? _retryTimer;
  bool _connected = false;
  bool _loading = false;
  bool _disposed = false;
  String? _route;
  int _generation = 0;
  int _retryIndex = 0;
  VelaExitIpInfo? _info;

  bool get connected => _connected;
  bool get loading => _loading;
  VelaExitIpInfo? get info => _info;
  String get label => _info?.label ?? (_loading ? '检测中…' : 'timeout');

  void sync(bool connected, String routeIdentity) {
    if (_disposed || (_connected == connected &&
        (!connected || _route == routeIdentity))) {
      return;
    }
    _generation++;
    _connected = connected;
    _route = connected ? routeIdentity : null;
    _probe.cancel();
    _timer?.cancel();
    _retryTimer?.cancel();
    _timer = null;
    _retryTimer = null;
    _retryIndex = 0;
    _loading = false;
    _info = null;
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
        if (result != null) {
          _info = result;
          _retryIndex = 0;
          _retryTimer?.cancel();
          _retryTimer = null;
        } else if (_info == null) {
          _scheduleRetry(generation);
        }
      }
    } catch (_) {
      if (!_disposed && _connected && generation == _generation &&
          _info == null) {
        _scheduleRetry(generation);
      }
    } finally {
      if (!_disposed && _connected && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
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
    _probe.cancel();
    super.dispose();
  }
}
