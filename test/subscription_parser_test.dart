import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_parser.dart';
import 'package:vela_shuo/src/mihomo/vela_mihomo_config.dart';

const _clashYaml = '''
proxies:
  - name: "Tokyo SS"
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: "secret1"
  - name: "London Trojan"
    type: trojan
    server: uk.example.test
    port: 443
    password: "secret2"
    sni: uk.example.test
  - name: "New York VLESS"
    type: vless
    server: us.example.test
    port: 8443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    servername: edge.example.test
    network: ws
    ws-opts:
      path: /hello
      headers:
        Host: edge.example.test
  - name: "Unsupported direct"
    type: direct
    server: test.example
    port: 80
  - name: "Insecure"
    type: trojan
    server: insecure.example
    port: 443
    password: secret
    skip-cert-verify: true
''';

void main() {
  test('Clash YAML imports compatible nodes, preserving TLS + WS metadata',
      () {
    final result = VelaSubscriptionParser.parse(_clashYaml);
    expect(result.format, 'Clash/Mihomo YAML');
    expect(result.nodes.map((n) => n.name),
        ['Tokyo SS', 'London Trojan', 'New York VLESS', 'Insecure']);
    expect(result.skipped, 1);
    final vless = result.nodes[2].outbound;
    expect(vless['type'], 'vless');
    expect(vless['uuid'], '11111111-2222-3333-4444-555555555555');
    final tls = vless['tls'] as Map<String, dynamic>;
    expect(tls['server_name'], 'edge.example.test');
    final transport = vless['transport'] as Map<String, dynamic>;
    expect(transport['type'], 'ws');
    expect(transport['path'], '/hello');
    expect((transport['headers'] as Map)['Host'], 'edge.example.test');
    expect(jsonDecode(const VelaMihomoConfigBuilder().build(result.nodes,
      selectedIndex: 2, secret: 'a' * 64, apiPort: null,
      proxyPort: 20808).configText)['rules'], ['MATCH,VELA_SELECT']);
  });

  test('sing-box JSON imports only independent secure outbounds', () {
    final input = jsonEncode({
      'outbounds': [
        {'type':'shadowsocks','tag':'SG-01',
         'server':'sg.example.test','server_port':443,
         'method':'aes-128-gcm','password':'secret'},
        {'type':'direct','tag':'direct'},
        {'type':'vless','tag':'insecure',
         'server':'us.example.test','server_port':443,
         'uuid':'11111111-2222-3333-4444-555555555555',
         'tls':{'enabled':true,'insecure':true}},
        {'type':'vless','tag':'detour',
         'server':'us.example.test','server_port':443,
         'uuid':'11111111-2222-3333-4444-555555555555',
         'detour':'other'},
      ],
    });
    final parsed = VelaSubscriptionParser.parse(input);
    expect(parsed.format, 'sing-box JSON');
    expect(parsed.nodes.single.name, 'SG-01');
    expect(parsed.skipped, 3);
    final config = jsonDecode(const VelaMihomoConfigBuilder().build(
      parsed.nodes, selectedIndex: 0, secret: 'a' * 64,
      proxyPort: 20808, apiPort: null).configText);
    expect(config['bind-address'], '127.0.0.1');
    expect(config['proxies'][0]['type'], 'ss');
    expect(config['rules'], ['MATCH,VELA_SELECT']);
    expect(config.toString(), isNot(contains('insecure')));
  });

  test('reject invalid text, oversized subscriptions and unsupported-only',
      () {
    expect(() => VelaSubscriptionParser.parse(''), throwsFormatException);
    expect(() => VelaSubscriptionParser.parse('{ not json'),
        throwsFormatException);
    expect(() => VelaSubscriptionParser.parse('proxies: []'),
        throwsFormatException);
    expect(() => VelaSubscriptionParser.parse(
        'x' * (VelaSubscriptionParser.maxBytes + 1)),
        throwsFormatException);
  });

  test('Reality parameters survive conversion without disabling TLS', () {
    const yaml = '''
proxies:
 - name: US reality
   type: vless
   server: us.example.test
   port: 443
   uuid: 11111111-2222-3333-4444-555555555555
   tls: true
   servername: www.example.test
   reality-opts:
     public-key: "example-public-key"
     short-id: "abcd"
''';
    final result = VelaSubscriptionParser.parse(yaml);
    final tls = result.nodes.single.outbound['tls'] as Map;
    expect((tls['reality'] as Map)['public_key'], 'example-public-key');
    expect((tls['reality'] as Map)['short_id'], 'abcd');
    expect(tls['enabled'], isTrue);
  });

  test('native Mihomo transport is kept verbatim instead of being downgraded', () {
    const yaml = '''
proxies:
 - name: unsupported
   type: vmess
   server: example.test
   port: 443
   uuid: 11111111-2222-3333-4444-555555555555
   network: h2
''';
    final parsed = VelaSubscriptionParser.parse(yaml);
    expect(parsed.nodes.single.clashProxy?['network'], 'h2');
    final generated = jsonDecode(const VelaMihomoConfigBuilder().build(
      parsed.nodes, selectedIndex: 0, secret: 'b' * 64,
      proxyPort: 20808, apiPort: null,
    ).configText) as Map<String, dynamic>;
    expect((generated['proxies'] as List).single['network'], 'h2');
  });

  test('FlClash/Mihomo native TUIC and AnyTLS are not dropped by Vela', () {
    const yaml = '''
proxies:
  - name: Tokyo TUIC
    type: tuic
    server: jp.example.test
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    password: abc123
    alpn: [h3]
    congestion-controller: bbr
  - name: Seoul AnyTLS
    type: anytls
    server: kr.example.test
    port: 443
    password: abc456
    idle-session-check-interval: 30
''';
    final parsed = VelaSubscriptionParser.parse(yaml);
    expect(parsed.nodes.map((n) => n.protocol), ['tuic', 'anytls']);
    final generated = jsonDecode(const VelaMihomoConfigBuilder().build(
      parsed.nodes, selectedIndex: 0, secret: 'c' * 64,
      proxyPort: 20808, apiPort: 20819,
    ).configText) as Map<String, dynamic>;
    final proxies = generated['proxies'] as List;
    expect(proxies[0]['congestion-controller'], 'bbr');
    expect(proxies[0]['alpn'], ['h3']);
    expect(proxies[1]['idle-session-check-interval'], 30);
    expect(generated, isNot(contains('tun')));
    expect(generated['allow-lan'], false);
  });

  test('imported remote controller, DNS and tunnel options are not forwarded', () {
    const yaml = '''
mixed-port: 9800
allow-lan: true
external-controller: 0.0.0.0:9000
tun: {enable: true}
proxies:
  - name: Valid Trojan
    type: trojan
    server: hk.example.test
    port: 443
    password: secret
''';
    final parsed = VelaSubscriptionParser.parse(yaml);
    final config = jsonDecode(const VelaMihomoConfigBuilder().build(
      parsed.nodes, selectedIndex: 0, secret: 'd' * 64,
      proxyPort: 20808, apiPort: 20819,
    ).configText) as Map<String, dynamic>;
    expect(config['mixed-port'], 20808);
    expect(config['allow-lan'], false);
    expect(config.containsKey('tun'), false);
    expect(config['external-controller'], '127.0.0.1:20819');
  });
}
