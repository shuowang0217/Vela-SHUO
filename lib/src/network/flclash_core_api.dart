import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// FlClash Go Core RPC. The methods and parameter encoding are from
/// chen08209/FlClash/core/method.go, not a second Vela proxy implementation.
///
/// Android transport: Vela MethodChannel -> FlClash Core.kt -> libcore.so
/// -> FlClash libclash.so. Windows will use the SAME wire protocol over the
/// FlClash named-pipe desktop transport, not the old single-node parser.
///
/// No UI widgets, subscription tokens or node credentials are logged here.
abstract interface class FlClashCoreTransport {
  Future<String?> invoke(String requestJson);
}

final class FlClashAndroidTransport implements FlClashCoreTransport {
  const FlClashAndroidTransport({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('vela_shuo/android_vpn');

  final MethodChannel _channel;

  @override
  Future<String?> invoke(String requestJson) {
    if (!Platform.isAndroid) {
      throw UnsupportedError('FlClash JNI transport requires Android');
    }
    return _channel.invokeMethod<String>(
        'coreMethod', <String, Object>{'data': requestJson});
  }
}

final class FlClashCoreFailure implements Exception {
  const FlClashCoreFailure(this.code, this.message);
  final String code;
  final String message;

  // Never send core-provided error content to generic logs: it could contain
  // subscription paths, hostnames, proxy credentials or private URLs.
  @override
  String toString() => 'FlClashCoreFailure($code)';
}

final class FlClashCoreApi {
  FlClashCoreApi(this.transport);
  final FlClashCoreTransport transport;
  int _sequence = 0;

  Future<Object?> invoke(
    String method, {
    Object? arguments,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final id = (++_sequence).toString();
    final request = jsonEncode(<String, Object?>{
      'id': id,
      'method': method,
      'arguments': arguments,
    });
    final raw = await transport.invoke(request).timeout(timeout);
    if (raw == null || raw.length > 16 * 1024 * 1024) {
      throw const FlClashCoreFailure('transport_error', 'Invalid native reply');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FlClashCoreFailure('invalid_response', 'Malformed native JSON');
    }
    if (decoded is! Map || decoded['id'] != id) {
      throw const FlClashCoreFailure('invalid_response', 'Incorrect request ID');
    }
    final error = decoded['error'];
    if (error is Map) {
      throw FlClashCoreFailure(
        error['code'] is String ? error['code'] as String : 'core_error',
        error['message'] is String ? error['message'] as String : 'Core error',
      );
    }
    return decoded['result'];
  }

  /// These are the FlClash Go method handlers, not a Vela configuration engine.
  Future<bool> initialize(String homeDir, {int androidApiLevel = 0}) async =>
      await invoke('initClash', arguments: {
        'home-dir': homeDir, 'version': androidApiLevel,
      }) == true;

  Future<Map<String, dynamic>> getConfig(String path) async {
    final value = await invoke('getConfig', arguments: path);
    if (value is! Map) {
      throw const FlClashCoreFailure('invalid_response', 'Expected core config');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<bool> startListener() async =>
      await invoke('startListener') == true;

  Future<bool> stopListener() async =>
      await invoke('stopListener') == true;

  Future<bool> shutdown() async =>
      await invoke('shutdown') == true;

  Future<Map<String, dynamic>> totalTraffic() async {
    final value = await invoke('getTotalTraffic', arguments: false);
    if (value is! Map) {
      throw const FlClashCoreFailure('invalid_response', 'Expected counters');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<String> validateConfig(String path) async =>
      await invoke('validateConfig', arguments: path) as String? ?? '';

  Future<List<String>> validateProxies(
      List<Map<String, Object?>> proxies) async {
    final value = await invoke('validateProxies', arguments: proxies);
    if (value is! List) {
      throw const FlClashCoreFailure('invalid_response', 'Expected errors list');
    }
    return value.cast<String>();
  }

  Future<Map<String, dynamic>> getProxies() async {
    final value = await invoke('getProxies');
    if (value is! Map) {
      throw const FlClashCoreFailure('invalid_response', 'Expected proxy map');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<bool> changeProxy(String groupName, String proxyName) async {
    final result = await invoke('changeProxy', arguments: {
      'group-name': groupName, 'proxy-name': proxyName,
    });
    if (result is! Map) {
      throw const FlClashCoreFailure('invalid_response', 'Expected switch result');
    }
    if (result['message'] case final String error when error.isNotEmpty) {
      throw FlClashCoreFailure('proxy_change_failed', error);
    }
    return result['changed'] == true;
  }

  Future<int?> testDelay(
      String proxyName, String url, {int timeoutMs = 5000}) async {
    final result = await invoke('asyncTestDelay', arguments: {
      'proxy-name': proxyName,
      'test-url': url,
      'timeout': timeoutMs,
    }, timeout: Duration(milliseconds: timeoutMs + 10000));
    if (result == null) return null;
    if (result is! Map || result['value'] is! num) {
      throw const FlClashCoreFailure('invalid_response', 'Expected delay');
    }
    final value = (result['value'] as num).toInt();
    return value >= 0 ? value : null;
  }

  Future<Map<String, dynamic>> getTraffic() async {
    final value = await invoke('getTraffic', arguments: false);
    if (value is! Map) {
      throw const FlClashCoreFailure('invalid_response', 'Expected traffic');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<List<dynamic>> getConnections() async {
    final result = await invoke('getConnections');
    if (result is! List) {
      throw const FlClashCoreFailure('invalid_response', 'Expected connections');
    }
    return result;
  }

  Future<List<dynamic>> getExternalProviders() async {
    final result = await invoke('getExternalProviders');
    if (result is! List) {
      throw const FlClashCoreFailure('invalid_response', 'Expected providers');
    }
    return result;
  }

  Future<String> updateExternalProvider(String name) async =>
      await invoke('updateExternalProvider', arguments: name,
          timeout: const Duration(minutes: 2)) as String? ?? '';

  Future<String> sideLoadExternalProvider(String providerName, String data) async =>
      await invoke('sideLoadExternalProvider', arguments: {
        'providerName': providerName, 'data': data,
      }) as String? ?? '';

  Future<String> setupConfig(
      {Map<String, String> selectedMap = const {},
      String testUrl = 'https://www.gstatic.com/generate_204'}) async =>
      await invoke('setupConfig', arguments: {
        'selected-map': selectedMap, 'test-url': testUrl,
      }, timeout: const Duration(minutes: 2)) as String? ?? '';

  /// Native FlClash Go: the first usable response is sent with the real
  /// Mihomo route chain and core/picks version. This works on Windows stdio
  /// and Android JNI without a second Dart HTTP/network stack.
  Future<Map<String, dynamic>?> outboundIp({
    required List<String> urls,
    int timeoutMs = 6000,
  }) async {
    final result = await invoke('outboundIp', arguments: {
      'proxy-name': '',
      'urls': urls,
      'timeout': timeoutMs,
    }, timeout: Duration(milliseconds: timeoutMs + 8000));
    if (result == null) return null;
    if (result is! Map) {
      throw const FlClashCoreFailure(
          'invalid_response', 'Invalid native outbound IP result');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Object?> probe(String url, String proxyName) => invoke('probe',
        arguments: {'url': url, 'proxy-name': proxyName,
                    'timeout': 8000, 'max-body': 2048, 'headers': <String,String>{}},
        timeout: const Duration(seconds: 16));
}
