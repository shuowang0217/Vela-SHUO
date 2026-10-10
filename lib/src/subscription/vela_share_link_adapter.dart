import 'dart:convert';

/// Decodes share URLs into Clash-style node maps; unsupported protocols,
/// insecure TLS and unknown transport options are rejected.
class VelaShareLinkAdapter {
  static final RegExp _link = RegExp(
    r'^(ss|vmess|vless|trojan|hysteria2|hy2)://', caseSensitive: false,
  );

  static bool looksLikeLinks(String input) =>
      input.split(RegExp(r'\r?\n')).any((line) => _link.hasMatch(line.trim()));

  static String? decodeBase64Subscription(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s'), '');
    if (compact.length < 24 ||
        !RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) { return null; }
    try {
      final decoded = utf8.decode(
        base64.decode(base64.normalize(compact)),
        allowMalformed: false,
      );
      return decoded.length <= 2 * 1024 * 1024 &&
          looksLikeLinks(decoded) ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _decode(String text) {
    try {
      return utf8.decode(
        base64.decode(base64.normalize(text.replaceAll(RegExp(r'\s'), ''))),
        allowMalformed: false,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? parseLink(String source) {
    try {
      final raw = source.trim();
      if (raw.length > 8192 || !_link.hasMatch(raw)) { return null; }
      final uri = Uri.parse(raw);
      switch (uri.scheme.toLowerCase()) {
        case 'ss':
          return _ss(uri, raw);
        case 'vmess':
          return _vmess(raw);
        case 'vless':
          return _vless(uri);
        case 'trojan':
          return _trojan(uri);
        case 'hy2':
        case 'hysteria2':
          return _hy2(uri);
      }
    } catch (_) {
      // Do not forward exception text: link may contain credentials.
    }
    return null;
  }

  static bool _server(String host) => host.isNotEmpty &&
      host.length <= 253 && !host.contains(RegExp(r'[\s/@\\]'));
  static bool _port(int port) => port >= 1 && port <= 65535;
  static String _name(Uri uri, String fallback) {
    final name = Uri.decodeComponent(uri.fragment).trim();
    return name.isEmpty ? fallback :
        name.length > 120 ? name.substring(0, 120) : name;
  }
  static bool _allow(Uri uri, Set<String> allowed) =>
      uri.queryParameters.keys.every(allowed.contains);
  static bool _secure(Uri uri) {
    for (final key in ['allowInsecure', 'insecure', 'skip-cert-verify']) {
      final val = uri.queryParameters[key]?.toLowerCase();
      if (val == '1' || val == 'true') return false;
    }
    return true;
  }

  static Map<String, dynamic>? _ss(Uri uri, String raw) {
    if (uri.queryParameters.isNotEmpty) { return null; } // No unsafe SIP002 plugin.
    final text = raw.substring(raw.indexOf('://') + 3)
        .split('#').first.split('?').first.replaceFirst(RegExp(r'/$'), '');
    String? creds;
    late final String serverPort;
    if (text.contains('@')) {
      final index = text.lastIndexOf('@');
      final encoded = Uri.decodeComponent(text.substring(0, index));
      creds = encoded.contains(':') ? encoded : _decode(encoded);
      serverPort = text.substring(index + 1);
    } else {
      final decoded = _decode(text);
      if (decoded == null || !decoded.contains('@')) { return null; }
      final index = decoded.lastIndexOf('@');
      creds = decoded.substring(0, index);
      serverPort = decoded.substring(index + 1);
    }
    if (creds == null || !creds.contains(':')) {
      return null;
    }
    final separator = creds.indexOf(':');
    final cipher = creds.substring(0, separator);
    final secret = creds.substring(separator + 1);
    final endpoint = Uri.tryParse('https://$serverPort');
    if (endpoint == null || !_port(endpoint.port) ||
        !_server(endpoint.host) || cipher.isEmpty || secret.isEmpty) {
      return null;
    }
    return {
      'name': _name(uri, 'Shadowsocks'),
      'type': 'ss',
      'server': endpoint.host,
      'port': endpoint.port,
      'cipher': cipher,
      'password': secret,
    };
  }

  static Map<String, dynamic>? _vmess(String raw) {
    final encoded = raw.substring(raw.indexOf('://') + 3).split('#').first;
    final decoded = _decode(encoded);
    if (decoded == null) { return null; }
    final data = jsonDecode(decoded);
    if (data is! Map) { return null; }
    final p = Map<String, dynamic>.from(data);
    if (p['allowInsecure'] == true || p['insecure'] == true ||
        (p['type'] != null && p['type'] != 'none')) { return null; }
    final tls = p['tls'] ?? '';
    if (tls != '' && tls != 'tls') { return null; }
    final net = p['net'] ?? 'tcp';
    if (net != 'tcp' && net != 'ws' && net != 'grpc') { return null; }
    final name = p['ps'];
    final node = <String, dynamic>{
      'name': name is String && name.isNotEmpty ? name : 'VMess',
      'type': 'vmess',
      'server': p['add'],
      'port': p['port'],
      'uuid': p['id'],
      'cipher': p['scy'] ?? 'auto',
      'alterId': int.tryParse(p['aid']?.toString() ?? '0') ?? 0,
      'tls': tls == 'tls',
      'servername': p['sni'] ?? p['host'],
      'network': net,
    };
    if (net == 'ws') {
      node['ws-opts'] = {
        'path': p['path'] is String ? p['path'] : '/',
        if (p['host'] is String && (p['host'] as String).isNotEmpty)
          'headers': {'Host': p['host']},
      };
    } else if (net == 'grpc') {
      node['grpc-opts'] = {'grpc-service-name': p['path'] ?? ''};
    }
    return node;
  }

  static Map<String, dynamic>? _basic(Uri uri, String type) {
    if (!_server(uri.host) || !_port(uri.port) || uri.userInfo.isEmpty) {
      return null;
    }
    return {
      'name': _name(uri, type.toUpperCase()),
      'type': type,
      'server': uri.host,
      'port': uri.port,
    };
  }

  static Map<String, dynamic>? _vless(Uri uri) {
    const allowed = {
      'encryption', 'security', 'sni', 'alpn', 'fp', 'pbk', 'sid',
      'type', 'host', 'path', 'serviceName', 'flow', 'headerType',
      'allowInsecure', 'insecure', 'skip-cert-verify',
    };
    if (!_allow(uri, allowed) || !_secure(uri)) { return null; }
    if (uri.queryParameters['encryption'] != null &&
        uri.queryParameters['encryption'] != 'none') { return null; }
    final security = uri.queryParameters['security'] ?? 'none';
    if (!['none', 'tls', 'reality'].contains(security)) { return null; }
    final node = _basic(uri, 'vless');
    if (node == null) { return null; }
    node['uuid'] = Uri.decodeComponent(uri.userInfo);
    node['tls'] = security != 'none';
    if (security == 'reality') {
      final key = uri.queryParameters['pbk'];
      if (key == null || key.isEmpty) { return null; }
      node['reality-opts'] = {
        'public-key': key,
        if (uri.queryParameters['sid'] != null)
          'short-id': uri.queryParameters['sid'],
      };
    }
    final flow = uri.queryParameters['flow'];
    if (flow != null && flow.isNotEmpty) node['flow'] = flow;
    _transport(node, uri);
    return node;
  }

  static Map<String, dynamic>? _trojan(Uri uri) {
    const allowed = {
      'security', 'sni', 'alpn', 'fp', 'type', 'host', 'path',
      'serviceName', 'headerType', 'allowInsecure', 'insecure',
      'skip-cert-verify',
    };
    if (!_allow(uri, allowed) || !_secure(uri)) { return null; }
    final security = uri.queryParameters['security'];
    if (security != null && security != 'tls') { return null; }
    final node = _basic(uri, 'trojan');
    if (node == null) { return null; }
    node['password'] = Uri.decodeComponent(uri.userInfo);
    _transport(node, uri);
    return node;
  }

  static Map<String, dynamic>? _hy2(Uri uri) {
    const allowed = {
      'sni', 'alpn', 'obfs', 'obfs-password',
      'allowInsecure', 'insecure', 'skip-cert-verify',
    };
    if (!_allow(uri, allowed) || !_secure(uri)) { return null; }
    final node = _basic(uri, 'hysteria2');
    if (node == null) { return null; }
    node['password'] = Uri.decodeComponent(uri.userInfo);
    final obfs = uri.queryParameters['obfs'];
    if (obfs != null) {
      if (obfs != 'salamander') { return null; }
      node['obfs'] = obfs;
      node['obfs-password'] = uri.queryParameters['obfs-password'];
    }
    _transport(node, uri);
    return node;
  }

  static void _transport(Map<String, dynamic> node, Uri uri) {
    final q = uri.queryParameters;
    if (q['sni'] != null) node['sni'] = q['sni'];
    if (q['alpn'] != null) node['alpn'] = q['alpn']!.split(',');
    if (q['fp'] != null) node['client-fingerprint'] = q['fp'];
    final network = q['type'] ?? 'tcp';
    node['network'] = network;
    if (network == 'ws') {
      node['ws-opts'] = {
        'path': q['path'] ?? '/',
        if (q['host'] != null) 'headers': {'Host': q['host']!},
      };
    } else if (network == 'grpc') {
      node['grpc-opts'] = {'grpc-service-name': q['serviceName'] ?? ''};
    } else if (network != 'tcp') {
      node['network'] = '__unsupported__';
    }
    if (q['headerType'] != null && q['headerType'] != 'none') {
      node['network'] = '__unsupported__';
    }
  }
}
