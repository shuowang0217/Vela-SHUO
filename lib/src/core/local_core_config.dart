import 'dart:convert';

/// Accept only loopback-only, no-TUN Mihomo JSON.
/// JSON is YAML-compatible; native Mihomo -t is the final validation.
class VelaLocalCoreConfig {
  const VelaLocalCoreConfig({required this.localPort, required this.inboundType, this.apiPort, this.apiSecret, this.selectorNames = const <String>[]});
  final int localPort;
  final String inboundType;
  final int? apiPort;
  final String? apiSecret;
  final List<String> selectorNames;
  static const maxBytes = 2 * 1024 * 1024;

  static VelaLocalCoreConfig parse(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('配置文件超过 2 MB 限制');
    }
    late final dynamic data;
    try {
      data = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Mihomo 配置不是有效 JSON');
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('配置根节点必须是 JSON 对象');
    }
    const allowed = {'mixed-port', 'allow-lan', 'bind-address', 'mode',
      'log-level', 'ipv6', 'external-controller', 'secret', 'proxies',
      'proxy-groups', 'rules'};
    if (data.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('配置包含不支持的网络监听或 TUN 字段');
    }
    final port = data['mixed-port'];
    if (port is! int || port < 1024 || port > 65535 ||
        data['bind-address'] != '127.0.0.1' ||
        data['allow-lan'] != false || data['ipv6'] != false ||
        data['mode'] != 'rule') {
      throw const FormatException('仅支持本机 127.0.0.1 mixed 代理与规则模式');
    }
    final controller = data['external-controller'];
    int? verifiedApiPort;
    String? verifiedSecret;
    if (controller != null) {
      final match = controller is String
          ? RegExp(r'^127\.0\.0\.1:(\d+)$').firstMatch(controller)
          : null;
      final apiPort = int.tryParse(match?.group(1) ?? '');
      final secret = data['secret'];
      if (apiPort == null || apiPort < 1024 || apiPort > 65535 ||
          apiPort == port || secret is! String || secret.length < 32 ||
          secret.length > 256 || !RegExp(r'^[a-fA-F0-9]+
        throw const FormatException('本机控制接口必须绑定 loopback 且启用密钥');
      }
      verifiedApiPort = apiPort;
      verifiedSecret = secret;
    } else if (data.containsKey('secret')) {
      throw const FormatException('未启用控制接口时不能配置 API 密钥');
    }
    final proxies = data['proxies'];
    final groups = data['proxy-groups'];
    final rules = data['rules'];
    if (proxies is! List || proxies.length > 500 ||
        groups is! List || rules is! List || rules.length != 1) {
      throw const FormatException('Mihomo 节点或规则字段不合法');
    }
    if (rules.single == 'MATCH,DIRECT') {
      if (proxies.isNotEmpty || groups.isNotEmpty) {
        throw const FormatException('直连配置不能包含代理节点');
      }
    } else if (rules.single == 'MATCH,VELA_SELECT') {
      if (proxies.isEmpty || groups.length != 1 ||
          groups.single is! Map ||
          groups.single['name'] != 'VELA_SELECT' ||
          groups.single['type'] != 'select' ||
          groups.single['proxies'] is! List ||
          (groups.single['proxies'] as List).isEmpty ||
          proxies.any((item) => item is! Map ||
              item['name'] is! String || item['type'] is! String)) {
        throw const FormatException('Mihomo 策略组或节点字段不合法');
      }
      final rawNames = groups.single['proxies'] as List;
      names = rawNames.whereType<String>().toList(growable: false);
      final proxyNames = proxies.map((p) => (p as Map)['name']).toSet();
      if (rawNames.length != names.length ||
          names.length != names.toSet().length ||
          names.any((name) => !proxyNames.contains(name))) {
        throw const FormatException('Mihomo 策略组节点与配置不一致');
      }
    } else {
      throw const FormatException('仅支持直连或 VELA_SELECT 策略');
    }
    return VelaLocalCoreConfig(localPort: port, inboundType: 'mixed');
  }
}
).hasMatch(secret)) {
        throw const FormatException('本机控制接口必须绑定 loopback 且启用密钥');
      }
    } else if (data.containsKey('secret')) {
      throw const FormatException('未启用控制接口时不能配置 API 密钥');
    }
    final proxies = data['proxies'];
    final groups = data['proxy-groups'];
    final rules = data['rules'];
    if (proxies is! List || proxies.length > 500 ||
        groups is! List || rules is! List || rules.length != 1) {
      throw const FormatException('Mihomo 节点或规则字段不合法');
    }
    if (rules.single == 'MATCH,DIRECT') {
      if (proxies.isNotEmpty || groups.isNotEmpty) {
        throw const FormatException('直连配置不能包含代理节点');
      }
    } else if (rules.single == 'MATCH,VELA_SELECT') {
      if (proxies.isEmpty || groups.length != 1 ||
          groups.single is! Map ||
          groups.single['name'] != 'VELA_SELECT' ||
          groups.single['type'] != 'select' ||
          groups.single['proxies'] is! List ||
          (groups.single['proxies'] as List).isEmpty ||
          proxies.any((item) => item is! Map ||
              item['name'] is! String || item['type'] is! String)) {
        throw const FormatException('Mihomo 策略组或节点字段不合法');
      }
    } else {
      throw const FormatException('仅支持直连或 VELA_SELECT 策略');
    }
    return VelaLocalCoreConfig(localPort: port, inboundType: 'mixed');
  }
}
