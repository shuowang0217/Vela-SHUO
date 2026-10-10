import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'vela_share_link_adapter.dart';

/// A supported, individually selectable remote outbound.
/// Credentials stay in memory until an explicitly selected node is started.
class VelaSubscriptionNode {
  const VelaSubscriptionNode({
    required this.name,
    required this.protocol,
    required this.server,
    required this.outbound,
  });

  final String name;
  final String protocol;
  final String server;
  final Map<String, dynamic> outbound;
}

class VelaSubscriptionResult {
  const VelaSubscriptionResult({
    required this.nodes,
    required this.skipped,
    required this.format,
  });

  final List<VelaSubscriptionNode> nodes;
  final int skipped;
  final String format;
}

/// Conservative translator for common Clash/Mihomo proxy entries and
/// sing-box JSON outbounds. Do NOT drop unsupported transport/security
/// options and pretend those nodes are valid.
class VelaSubscriptionParser {
  static const maxBytes = 2 * 1024 * 1024;
  static const maxNodes = 500;
  static const supported = {
    'ss', 'shadowsocks', 'vmess', 'vless', 'trojan', 'hysteria2',
  };

  static VelaSubscriptionResult parse(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('订阅内容超过 2 MB');
    }
    final source = raw.replaceFirst('\uFEFF', '').trim();
    if (source.isEmpty) throw const FormatException('订阅内容为空');

    // First classify the response, rather than treating a base64 payload or
    // HTML login page as a malformed YAML root.
    if (source.startsWith('<!') || source.startsWith('<html') ||
        source.startsWith('<HTML')) {
      throw const FormatException(
        '服务器返回的是网页而不是节点订阅，请在服务商面板复制专用订阅地址',
      );
    }

    if (VelaShareLinkAdapter.looksLikeLinks(source)) {
      return _parseShareLinks(source, '节点分享链接');
    }
    final decoded = VelaShareLinkAdapter.decodeBase64Subscription(source);
    if (decoded != null) {
      return _parseShareLinks(decoded, 'Base64 通用订阅');
    }

    dynamic root;
    try {
      root = jsonDecode(source);
    } on FormatException {
      try {
        root = loadYaml(source);
      } catch (_) {
        throw const FormatException(
          '无法识别订阅内容，请使用 Clash/Mihomo、sing-box 或通用节点订阅',
        );
      }
    }
    if (root is String) {
      if (VelaShareLinkAdapter.looksLikeLinks(root)) {
        return _parseShareLinks(root, '节点分享链接');
      }
      final nested = VelaShareLinkAdapter.decodeBase64Subscription(root);
      if (nested != null) return _parseShareLinks(nested, 'Base64 通用订阅');
      throw const FormatException(
        '订阅返回的是文本而非节点列表，可能是服务商提示或订阅格式不匹配',
      );
    }
    if (root is List) {
      final lines = root.whereType<String>().join('\n');
      if (VelaShareLinkAdapter.looksLikeLinks(lines)) {
        return _parseShareLinks(lines, '节点链接列表');
      }
      throw const FormatException(
        '订阅返回的是数组，但没有识别到受支持的节点分享链接',
      );
    }
    if (root is! Map) {
      throw const FormatException('订阅内容不是受支持的节点配置');
    }
    final data = _plain(root);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('订阅结构不正确');
    }
    final isClash = data['proxies'] is List;
    final candidates = isClash ? data['proxies'] : data['outbounds'];
    if (candidates is! List) {
      throw const FormatException(
        '没有找到节点列表，可能下载了订阅说明页；请尝试 Clash 专用链接',
      );
    }
    final format = isClash ? 'Clash/Mihomo YAML' : 'sing-box JSON';
    if (candidates.length > maxNodes) {
      throw const FormatException('单份订阅最多支持 500 个节点');
    }
    final nodes = <VelaSubscriptionNode>[];
    var skipped = 0;
    for (final candidate in candidates) {
      try {
        if (candidate is! Map<String, dynamic>) {
          skipped++;
          continue;
        }
        final node = isClash
            ? _fromClash(candidate)
            : _fromSingBox(candidate);
        if (node == null) {
          skipped++;
        } else {
          nodes.add(node);
        }
      } catch (_) {
        skipped++;
      }
    }
    if (nodes.isEmpty) {
      throw const FormatException('没有可用节点；请检查订阅类型与协议支持范围');
    }
    return VelaSubscriptionResult(
      nodes: List.unmodifiable(nodes), skipped: skipped, format: format,
    );
  }

  static VelaSubscriptionResult _parseShareLinks(
    String raw, String format,
  ) {
    final lines = raw.split(RegExp(r'\r?\n')).map((s) => s.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#')).toList();
    if (lines.length > maxNodes) {
      throw const FormatException('单份订阅最多支持 500 个节点');
    }
    final nodes = <VelaSubscriptionNode>[];
    var skipped = 0;
    for (final line in lines) {
      final candidate = VelaShareLinkAdapter.parseLink(line);
      if (candidate == null) {
        skipped++;
        continue;
      }
      try {
        final node = _fromClash(candidate);
        if (node == null) {
          skipped++;
        } else {
          nodes.add(node);
        }
      } catch (_) {
        skipped++;
      }
    }
    if (nodes.isEmpty) {
      throw const FormatException(
        '检测到节点分享链接，但协议或安全参数暂不兼容；请尝试 Clash 订阅',
      );
    }
    return VelaSubscriptionResult(
      nodes: List.unmodifiable(nodes), skipped: skipped, format: format,
    );
  }

  static dynamic _plain(dynamic item) {
    if (item is Map) {
      return <String, dynamic>{
        for (final entry in item.entries) entry.key.toString(): _plain(entry.value),
      };
    }
    if (item is List) { return item.map(_plain).toList(); }
    return item;
  }

  static bool _validServer(dynamic server) {
    if (server is! String || server.isEmpty || server.length > 253) {
      return false;
    }
    return !server.contains(RegExp(r'[\s/@\\]'));
  }

  static int? _port(dynamic p) {
    final value = p is int ? p : int.tryParse(p?.toString() ?? '');
    return value != null && value >= 1 && value <= 65535 ? value : null;
  }

  static String? _name(dynamic value) {
    if (value is! String) { return null; }
    final v = value.trim();
    return v.isNotEmpty && v.length <= 120 ? v : null;
  }

  static String? _secret(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  static bool _safeTls(Map<String, dynamic> source) {
    // No weakening of certificate validation in an automatic import.
    return source['skip-cert-verify'] != true &&
        source['allowInsecure'] != true &&
        source['insecure'] != true;
  }

  static Map<String, dynamic>? _tls(Map<String, dynamic> p,
      {required bool enabled}) {
    if (!_safeTls(p)) { return null; }
    if (!enabled) { return <String, dynamic>{}; }
    final tls = <String, dynamic>{'enabled': true};
    final serverName = p['servername'] ?? p['sni'];
    if (serverName is String && serverName.isNotEmpty) {
      tls['server_name'] = serverName;
    }
    final alpn = p['alpn'];
    if (alpn is List && alpn.every((e) => e is String)) {
      tls['alpn'] = List<String>.from(alpn);
    }
    final finger = p['client-fingerprint'];
    if (finger is String && finger.isNotEmpty) {
      tls['utls'] = {'enabled': true, 'fingerprint': finger};
    }
    final reality = p['reality-opts'];
    if (reality != null) {
      if (reality is! Map<String, dynamic> ||
          _secret(reality['public-key']) == null) { return null; }
      tls['reality'] = {
        'enabled': true,
        'public_key': reality['public-key'],
        if (reality['short-id'] is String) 'short_id': reality['short-id'],
      };
    }
    return tls;
  }

  static Map<String, dynamic>? _transport(Map<String, dynamic> p) {
    final network = p['network'] ?? 'tcp';
    if (network == 'tcp') { return {}; }
    if (network == 'ws') {
      final options = p['ws-opts'] ?? {};
      if (options is! Map<String, dynamic>) { return null; }
      final transport = <String, dynamic>{
        'type': 'ws',
        'path': options['path'] is String ? options['path'] : '/',
      };
      final headers = options['headers'];
      if (headers != null) {
        if (headers is! Map<String, dynamic> ||
            headers.values.any((x) => x is! String)) { return null; }
        transport['headers'] = headers;
      }
      return transport;
    }
    if (network == 'grpc') {
      final options = p['grpc-opts'] ?? {};
      if (options is! Map<String, dynamic>) { return null; }
      return {
        'type': 'grpc',
        'service_name': options['grpc-service-name'] is String
            ? options['grpc-service-name'] : '',
      };
    }
    return null;
  }

  static VelaSubscriptionNode? _fromClash(Map<String, dynamic> p) {
    final type = p['type'];
    final name = _name(p['name']);
    final server = p['server'];
    final port = _port(p['port']);
    if (type is! String || !supported.contains(type) ||
        name == null || !_validServer(server) || port == null) { return null; }
    final kind = type == 'ss' ? 'shadowsocks' : type;
    final outbound = <String, dynamic>{
      'type': kind, 'tag': 'selected',
      'server': server, 'server_port': port,
    };

    if (!_safeTls(p)) { return null; }
    if (type == 'ss') {
      if (p['plugin'] != null || p['plugin-opts'] != null ||
          _secret(p['cipher']) == null ||
          _secret(p['password']) == null) { return null; }
      outbound.addAll({'method': p['cipher'], 'password': p['password']});
    } else if (type == 'vmess' || type == 'vless') {
      final id = _secret(p['uuid']);
      if (id == null) { return null; }
      outbound['uuid'] = id;
      if (type == 'vmess') {
        outbound['security'] = p['cipher'] is String ? p['cipher'] : 'auto';
        outbound['alter_id'] = p['alterId'] is int ? p['alterId'] : 0;
      } else if (p['flow'] is String && (p['flow'] as String).isNotEmpty) {
        outbound['flow'] = p['flow'];
      }
      final hasTls = p['tls'] == true || p['reality-opts'] != null;
      final tls = _tls(p, enabled: hasTls);
      if (tls == null) { return null; }
      if (hasTls) outbound['tls'] = tls;
      final transport = _transport(p);
      if (transport == null) { return null; }
      if (transport.isNotEmpty) outbound['transport'] = transport;
    } else if (type == 'trojan' || type == 'hysteria2') {
      if (_secret(p['password']) == null) { return null; }
      outbound['password'] = p['password'];
      final tls = _tls(p, enabled: true);
      if (tls == null) { return null; }
      outbound['tls'] = tls;
      if (type == 'trojan') {
        final transport = _transport(p);
        if (transport == null) { return null; }
        if (transport.isNotEmpty) outbound['transport'] = transport;
      } else {
        final obfs = p['obfs'];
        if (obfs != null) {
          if (obfs != 'salamander' || _secret(p['obfs-password']) == null) {
            return null;
          }
          outbound['obfs'] = {'type': 'salamander',
            'password': p['obfs-password']};
        }
      }
    }
    return VelaSubscriptionNode(
      name: name, protocol: kind, server: server as String, outbound: outbound,
    );
  }

  static VelaSubscriptionNode? _fromSingBox(Map<String, dynamic> p) {
    final type = p['type'];
    final name = _name(p['tag']);
    final server = p['server'];
    final port = _port(p['server_port']);
    if (type is! String || !supported.contains(type) || type == 'ss' ||
        name == null || !_validServer(server) || port == null) { return null; }
    final tls = p['tls'];
    if (tls is Map<String, dynamic> && tls['insecure'] == true) { return null; }
    if (p['detour'] != null) { return null; }
    if (type == 'shadowsocks' &&
        (_secret(p['method']) == null || _secret(p['password']) == null)) {
      return null;
    }
    if ((type == 'vmess' || type == 'vless') &&
        _secret(p['uuid']) == null) { return null; }
    if ((type == 'trojan' || type == 'hysteria2') &&
        _secret(p['password']) == null) { return null; }
    final outbound = Map<String, dynamic>.from(p)..['tag'] = 'selected';
    return VelaSubscriptionNode(
      name: name, protocol: type, server: server as String, outbound: outbound,
    );
  }

  static String buildConfig(VelaSubscriptionNode node, {int port = 20808}) {
    if (port < 1024 || port > 65535) {
      throw const FormatException('本地端口无效');
    }
    // Apply only the outbound for the selected node, not arbitrary inbound,
    // DNS or system-route settings from the subscription document.
    return jsonEncode({
      'log': {'level': 'warn'},
      'inbounds': [
        {'type': 'mixed', 'tag': 'vela-local',
          'listen': '127.0.0.1', 'listen_port': port},
      ],
      'outbounds': [node.outbound, {'type':'direct', 'tag':'direct'}],
      'route': {'final': 'selected'},
    });
  }
}
