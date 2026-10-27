import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Public exit observed by an HTTPS endpoint, not a country guessed from the
/// selected node name. Never persisted or sent to diagnostics.
class VelaExitIpInfo {
  const VelaExitIpInfo({required this.address, required this.countryCode});

  final String address;
  final String countryCode;

  String get flag => String.fromCharCodes([
    127397 + countryCode.codeUnitAt(0),
    127397 + countryCode.codeUnitAt(1),
  ]);

  String get label => '$flag $address';

  /// Cloudflare's /cdn-cgi/trace has "ip=" and "loc=" lines.
  /// Reject malformed/partial responses instead of displaying a guessed flag.
  static VelaExitIpInfo? parseTrace(String body) {
    if (body.length > 4096) return null;
    final fields = <String, String>{};
    for (final line in const LineSplitter().convert(body)) {
      final equal = line.indexOf('=');
      if (equal <= 0) continue;
      fields[line.substring(0, equal)] = line.substring(equal + 1).trim();
    }
    final ip = fields['ip'];
    final country = fields['loc'];
    if (ip == null || country == null ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(country)) return null;
    final address = InternetAddress.tryParse(ip);
    if (address == null || address.isLoopback ||
        address.isLinkLocal || address.isMulticast ||
        (address.type != InternetAddressType.IPv4 &&
         address.type != InternetAddressType.IPv6)) return null;
    return VelaExitIpInfo(address: ip, countryCode: country);
  }

  /// Alternate endpoint is used only if the Cloudflare trace is unavailable.
  static VelaExitIpInfo? parseCountryResponse(String body) {
    if (body.length > 4096) return null;
    try {
      final response = jsonDecode(body);
      if (response is! Map || response['ip'] is! String ||
          response['country'] is! String) return null;
      return parseTrace('ip=' + (response['ip'] as String) + '\nloc=' +
          (response['country'] as String) + '\n');
    } catch (_) {
      return null;
    }
  }
}

/// Windows MUST use Mihomo's local mixed HTTP proxy (never a DIRECT fallback).
/// Android sockets use the already-established Android VPN TUN.
class VelaExitIpProbe {
  HttpClient? _active;
  int _generation = 0;

  Future<VelaExitIpInfo?> lookup({required bool useProxy, int? proxyPort}) async {
    if (useProxy && (proxyPort == null || proxyPort < 1 ||
        proxyPort > 65535)) return null;
    final generation = _generation;
    final endpoints = <(Uri, VelaExitIpInfo? Function(String))>[
      (Uri.https('www.cloudflare.com', '/cdn-cgi/trace'),
          VelaExitIpInfo.parseTrace),
      (Uri.https('api.country.is', '/'),
          VelaExitIpInfo.parseCountryResponse),
    ];
    for (final (url, parse) in endpoints) {
      if (generation != _generation) return null;
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      _active = client;
      if (useProxy) {
        client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
      }
      try {
        final request = await client.getUrl(url)
            .timeout(const Duration(seconds: 6));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'text/plain, application/json');
        final response = await request.close()
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > 4096) continue;
        final body = <int>[];
        var tooLarge = false;
        await for (final chunk in response.timeout(const Duration(seconds: 6))) {
          if (body.length + chunk.length > 4096) {
            tooLarge = true;
            break;
          }
          body.addAll(chunk);
        }
        if (tooLarge || generation != _generation) return null;
        final result = parse(utf8.decode(body));
        if (result != null) return result;
      } catch (_) {
        // A blocked detection endpoint is not proof that the VPN is broken.
        // Try the second service using the same enforced proxy/VPN route.
      } finally {
        if (identical(_active, client)) _active = null;
        client.close(force: true);
      }
    }
    return null;
  }

  void cancel() {
    _generation++;
    _active?.close(force: true);
    _active = null;
  }
}

/// The old IP must disappear immediately on disconnect, route change or
/// failed detection. A generation check rejects late responses from old nodes.
class VelaExitIpMonitor extends ChangeNotifier {
  VelaExitIpMonitor({
    required this.useProxy,
    required this.proxyPort,
    VelaExitIpProbe? probe,
    Duration interval = const Duration(minutes: 2),
  }) : _probe = probe ?? VelaExitIpProbe(), _interval = interval;

  final bool useProxy;
  final int? Function() proxyPort;
  final VelaExitIpProbe _probe;
  final Duration _interval;

  Timer? _timer;
  bool _connected = false;
  bool _loading = false;
  bool _disposed = false;
  String? _route;
  int _generation = 0;
  VelaExitIpInfo? _info;

  bool get connected => _connected;
  bool get loading => _loading;
  VelaExitIpInfo? get info => _info;
  String get label => _info?.label ?? (_loading ? '检测中…' : 'timeout');

  void sync(bool connected, String routeIdentity) {
    if (_disposed || (_connected == connected &&
        (!connected || _route == routeIdentity))) return;
    _generation++;
    _connected = connected;
    _route = connected ? routeIdentity : null;
    _probe.cancel();
    _timer?.cancel();
    _timer = null;
    _loading = false;
    _info = null;
    notifyListeners();
    if (connected) {
      unawaited(refresh());
      _timer = Timer.periodic(_interval, (_) => unawaited(refresh()));
    }
  }

  Future<void> refresh() async {
    if (_disposed || !_connected || _loading) return;
    final generation = _generation;
    _loading = true;
    _info = null;
    notifyListeners();
    try {
      final result = await _probe.lookup(
        useProxy: useProxy,
        proxyPort: useProxy ? proxyPort() : null,
      );
      if (!_disposed && _connected && generation == _generation) {
        _info = result;
      }
    } catch (_) {
      if (!_disposed && _connected && generation == _generation) {
        _info = null;
      }
    } finally {
      if (!_disposed && _connected && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _probe.cancel();
    super.dispose();
  }
}
