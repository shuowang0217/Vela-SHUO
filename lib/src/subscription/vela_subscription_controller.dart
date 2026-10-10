import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/vela_core_controller.dart';
import 'vela_subscription_parser.dart';

/// The subscription is fetched only after the user explicitly requests it.
/// Neither its URL (usually a bearer token) nor node credentials are logged
/// or stored in SharedPreferences.
abstract class VelaSubscriptionFetcher {
  Future<String> download(String source);
}

class VelaHttpsSubscriptionFetcher implements VelaSubscriptionFetcher {
  const VelaHttpsSubscriptionFetcher();

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
    Uri uri;
    try {
      uri = Uri.parse(source.trim());
    } catch (_) {
      throw const FormatException('订阅地址格式不正确');
    }
    _validateUrl(uri);
    // Check DNS before fetching, disable redirects and proxy usage. This
    // narrows SSRF risk; this is NOT a substitute for DNS pinning / sandboxing.
    await _checkDns(uri.host);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.findProxy = (_) => 'DIRECT';
    client.userAgent = 'Vela-SHUO/0.2';
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      req.followRedirects = false; // Never leak bearer URL via 30x redirect.
      req.headers.set(HttpHeaders.acceptHeader,
          'application/json, application/yaml, text/yaml, text/plain');
      final response = await req.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException('订阅服务器返回非成功状态（或重定向）');
      }
      final parts = <int>[];
      await for (final chunk in response.timeout(
        const Duration(seconds: 15),
      )) {
        parts.addAll(chunk);
        if (parts.length > VelaSubscriptionParser.maxBytes) {
          throw const FormatException('订阅数据超过 2 MB 限制');
        }
      }
      try {
        return utf8.decode(parts, allowMalformed: false);
      } catch (_) {
        throw const FormatException('订阅不是 UTF-8 文本');
      }
    } on FormatException {
      rethrow;
    } on TimeoutException {
      throw const FormatException('获取订阅超时');
    } on HandshakeException {
      throw const FormatException('订阅 HTTPS 证书验证失败');
    } catch (_) {
      throw const FormatException('订阅下载失败，请检查链接与网络');
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
  int? _selected;
  String? _error;
  bool _disposed = false;
  int _generation = 0;

  VelaSubscriptionPhase get phase => _phase;
  List<VelaSubscriptionNode> get nodes => _result?.nodes ?? const [];
  int get skipped => _result?.skipped ?? 0;
  String? get format => _result?.format;
  int? get selectedIndex => _selected;
  String? get error => _error;
  bool get loading => _phase == VelaSubscriptionPhase.loading;
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
    _selected = null;
    final generation = ++_generation;
    _notify();
    try {
      final raw = await _fetcher.download(url);
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
    final node = nodes[index];
    final ok = await core.useRemoteSubscriptionProfile(
      VelaSubscriptionParser.buildConfig(node),
    );
    if (ok) {
      _selected = index;
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
    _selected = null;
    _disposed = true;
    super.dispose();
  }
}
