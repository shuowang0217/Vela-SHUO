// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';

import '../subscription/vela_subscription_parser.dart';

/// Translation is allowlisted; unknown/insecure fields are never forwarded.
class VelaMihomoEntry {
  const VelaMihomoEntry(this.index, this.name, this.proxy);
  final int index;
  final String name;
  final Map<String, dynamic> proxy;
}

class VelaMihomoConfiguration {
  const VelaMihomoConfiguration(this.configText, this.entries);
  static const proxyPort = 20818;
  static const apiPort = 20819;
  static const group = 'VELA_SELECT';
  final String configText;
  final List<VelaMihomoEntry> entries;

  String? nameFor(int index) {
    for (final entry in entries) {
      if (entry.index == index) { return entry.name; }
    }
    return null;
  }
}

class VelaMihomoConfigBuilder {
  const VelaMihomoConfigBuilder();

  VelaMihomoConfiguration build(List<VelaSubscriptionNode> nodes, {
    required int selectedIndex, required String secret,
    int proxyPort = VelaMihomoConfiguration.proxyPort,
    int? apiPort = VelaMihomoConfiguration.apiPort,
  }) {
    if (nodes.isEmpty || nodes.length > 500 ||
        selectedIndex < 0 || selectedIndex >= nodes.length ||
        secret.length < 32 || secret.length > 256 ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(secret) ||
        proxyPort < 1024 || proxyPort > 65535 ||
        (apiPort != null && (apiPort < 1024 || apiPort > 65535 || apiPort == proxyPort))) {
      throw const FormatException('Mihomo 实验配置参数不合法');
    }
    final entries = <VelaMihomoEntry>[];
    final used = <String>{VelaMihomoConfiguration.group, 'DIRECT'};
    for (var i = 0; i < nodes.length; i++) {
      final proxy = _translate(nodes[i].outbound);
      if (proxy == null) { continue; }
      var name = nodes[i].name.trim();
      if (name.isEmpty || name.length > 120) { continue; }
      if (used.contains(name)) {
        var suffix = 2;
        while (used.contains(name + ' (' + suffix.toString() + ')')) {
          suffix++;
        }
        name = name + ' (' + suffix.toString() + ')';
      }
      used.add(name);
      proxy['name'] = name;
      entries.add(VelaMihomoEntry(i, name, proxy));
    }
    final selected = entries.where((e) => e.index == selectedIndex).toList();
    if (selected.length != 1) {
      throw const FormatException('所选节点暂不支持 Mihomo 实验内核');
    }
    final labels = [selected.single.name,
      ...entries.where((e) => e.index != selectedIndex).map((e) => e.name)];
    // JSON is a YAML subset and safely escapes arbitrary node labels.
    return VelaMihomoConfiguration(jsonEncode(<String, dynamic>{
      'mixed-port': proxyPort,
      'allow-lan': false,
      'bind-address': '127.0.0.1',
      'mode': 'rule',
      'log-level': 'warning',
      'ipv6': false,
      if (apiPort != null) 'external-controller': '127.0.0.1:$apiPort',
      if (apiPort != null) 'secret': secret,
      'proxies': entries.map((e) => e.proxy).toList(),
      'proxy-groups': [{
        'name': VelaMihomoConfiguration.group,
        'type': 'select',
        'proxies': labels,
      }],
      'rules': ['MATCH,VELA_SELECT'],
    }), List.unmodifiable(entries));
  }

  static Map<String, dynamic>? _translate(Map<String, dynamic> o) {
    final type = o['type'], server = o['server'], port = o['server_port'];
    if (!{'shadowsocks', 'vmess', 'vless', 'trojan', 'hysteria2'}
            .contains(type) ||
        server is! String || server.isEmpty || server.length > 253 ||
        server.contains(RegExp(r'[\s/@\\]')) ||
        port is! int || port < 1 || port > 65535) { return null; }
    final tls = o['tls'];
    if (tls != null && (tls is! Map || tls['enabled'] != true ||
        tls['insecure'] == true)) { return null; }
    final result = <String, dynamic>{
      'type': type == 'shadowsocks' ? 'ss' : type,
      'server': server, 'port': port,
    };
    if (type == 'shadowsocks') {
      if (!_str(o['method']) || !_str(o['password']) ||
          o['plugin'] != null) { return null; }
      result['cipher'] = o['method'];
      result['password'] = o['password'];
      return result;
    }
    if (type == 'vmess' || type == 'vless') {
      if (!_str(o['uuid'])) { return null; }
      result['uuid'] = o['uuid'];
      if (type == 'vmess') {
        if (tls is Map && tls['reality'] != null) { return null; }
        result['cipher'] = o['security'] is String ? o['security'] : 'auto';
        result['alterId'] = o['alter_id'] is int ? o['alter_id'] : 0;
      } else if (o['flow'] is String) {
        result['flow'] = o['flow'];
      }
      result['tls'] = tls != null;
    } else {
      if (!_str(o['password'])) { return null; }
      result['password'] = o['password'];
    }
    if (tls != null) {
      if (tls is! Map) { return null; }
      if (tls['server_name'] is String) {
        result[type == 'trojan' || type == 'hysteria2'
            ? 'sni' : 'servername'] = tls['server_name'];
      }
      final alpn = tls['alpn'];
      if (alpn != null) {
        if (alpn is! List || alpn.any((v) => v is! String)) {
          return null;
        }
        result['alpn'] = alpn;
      }
      final utls = tls['utls'];
      if (utls != null) {
        if (utls is! Map || utls['enabled'] != true ||
            !_str(utls['fingerprint'])) { return null; }
        result['client-fingerprint'] = utls['fingerprint'];
      }
      final reality = tls['reality'];
      if (reality != null) {
        if (type != 'vless' || reality is! Map ||
            reality['enabled'] != true ||
            !_str(reality['public_key'])) { return null; }
        result['reality-opts'] = {
          'public-key': reality['public_key'],
          if (reality['short_id'] is String)
            'short-id': reality['short_id'],
        };
      }
    }
    final transport = o['transport'];
    if (transport != null) {
      if (transport is! Map || type == 'hysteria2') { return null; }
      if (transport['type'] == 'ws') {
        final headers = transport['headers'];
        if (headers != null && (headers is! Map ||
            headers.values.any((v) => v is! String))) { return null; }
        result['network'] = 'ws';
        final wsOptions = <String, dynamic>{
          'path': transport['path'] is String ? transport['path'] : '/',
        };
        if (headers != null) { wsOptions['headers'] = headers; }
        result['ws-opts'] = wsOptions;
      } else if (transport['type'] == 'grpc') {
        result['network'] = 'grpc';
        result['grpc-opts'] = {
          'grpc-service-name': transport['service_name'] is String
              ? transport['service_name'] : '',
        };
      } else {
        return null;
      }
    }
    if (type == 'hysteria2' && o['obfs'] != null) {
      final obfs = o['obfs'];
      if (obfs is! Map || obfs['type'] != 'salamander' ||
          !_str(obfs['password'])) { return null; }
      result['obfs'] = 'salamander';
      result['obfs-password'] = obfs['password'];
    }
    return result;
  }

  static bool _str(Object? value) => value is String && value.isNotEmpty;
}
