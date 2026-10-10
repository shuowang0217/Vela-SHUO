import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_parser.dart';

void main() {
  test('base64 universal subscription decodes SS and VLESS share links', () {
    const links = '''
ss://YWVzLTEyOC1nY206c2VjcmV0@jp.example.test:443#Tokyo
vless://11111111-2222-3333-4444-555555555555@us.example.test:443?security=tls&sni=edge.example.test&type=ws&host=edge.example.test&path=%2Fconnect#US
unknown://something-private
''';
    final base = base64.encode(utf8.encode(links));
    final imported = VelaSubscriptionParser.parse(base);
    expect(imported.format, 'Base64 通用订阅');
    expect(imported.nodes.map((n) => n.protocol),
        ['shadowsocks', 'vless']);
    expect(imported.nodes.map((n) => n.name), ['Tokyo', 'US']);
    expect(imported.skipped, 1);
    final tls = imported.nodes[1].outbound['tls'] as Map;
    expect(tls['server_name'], 'edge.example.test');
    final transport = imported.nodes[1].outbound['transport'] as Map;
    expect(transport['path'], '/connect');
    expect((transport['headers'] as Map)['Host'], 'edge.example.test');
    final config = jsonDecode(
        VelaSubscriptionParser.buildConfig(imported.nodes[0])) as Map;
    expect(config['inbounds'][0]['listen'], '127.0.0.1');
  });

  test('legacy full-base64 SS and SIP002 userinfo formats both work', () {
    final full = base64.encode(
        utf8.encode('aes-256-gcm:another-secret@sg.example.test:8388'));
    final creds = base64Url.encode(utf8.encode('aes-128-gcm:pass'))
        .replaceAll('=', '');
    final result = VelaSubscriptionParser.parse(
      'ss://$full#SG\nss://$creds@us.example.test:443#US',
    );
    expect(result.nodes.length, 2);
    expect(result.nodes.first.outbound['password'], 'another-secret');
    expect(result.nodes.last.outbound['password'], 'pass');
    expect(result.skipped, 0);
  });

  test('VMess base64 JSON preserves TLS and WebSocket transport', () {
    final vmess = {
      'v':'2', 'ps':'London VMess', 'add':'uk.example.test',
      'port':'443', 'id':'11111111-2222-3333-4444-555555555555',
      'aid':'0', 'scy':'auto', 'net':'ws', 'host':'host.example.test',
      'path':'/ws', 'tls':'tls', 'sni':'edge.example.test',
    };
    final encoded = base64Url.encode(utf8.encode(jsonEncode(vmess)));
    final link = 'vmess://$encoded';
    final result = VelaSubscriptionParser.parse(link);
    expect(result.nodes.single.protocol, 'vmess');
    expect(result.nodes.single.outbound['alter_id'], 0);
    final transport = result.nodes.single.outbound['transport'] as Map;
    expect(transport['type'], 'ws');
    expect(transport['path'], '/ws');
    expect((transport['headers'] as Map)['Host'], 'host.example.test');
  });

  test('VLESS Reality, Trojan and Hysteria2 share links are supported', () {
    const links = '''
vless://11111111-2222-3333-4444-555555555555@reality.example.test:443?security=reality&sni=www.example.com&pbk=public-key&sid=abcd&type=tcp#Reality
trojan://secret@trojan.example.test:443?security=tls&sni=example.test#Trojan
hy2://password@hysteria.example.test:443?sni=example.test&obfs=salamander&obfs-password=mask#Hy2
''';
    final parsed = VelaSubscriptionParser.parse(links);
    expect(parsed.nodes.map((n) => n.protocol),
      ['vless', 'trojan', 'hysteria2']);
    final reality = (parsed.nodes[0].outbound['tls'] as Map)['reality'] as Map;
    expect(reality['public_key'], 'public-key');
    expect(parsed.nodes[2].outbound['obfs'], {
      'type': 'salamander', 'password': 'mask',
    });
  });

  test('unknown transport and insecure TLS are skipped, never downgraded', () {
    const links = '''
vless://11111111-2222-3333-4444-555555555555@bad.example.test:443?security=tls&type=xhttp#Unsupported
trojan://secret@bad.example.test:443?security=tls&allowInsecure=1#Unsafe
ss://YWVzLTEyOC1nY206c2VjcmV0@good.example.test:443#Valid
''';
    final parsed = VelaSubscriptionParser.parse(links);
    expect(parsed.nodes.single.name, 'Valid');
    expect(parsed.skipped, 2);
  });

  test('login HTML and non-node replies have safe targeted messages', () {
    for (final page in [
      '<!doctype html><html><body>secret_token_123</body></html>',
      '<html>please login</html>',
    ]) {
      try {
        VelaSubscriptionParser.parse(page);
        fail('HTML should not be recognized as a subscription');
      } on FormatException catch (e) {
        expect(e.message, contains('网页'));
        expect(e.message, isNot(contains('secret_token_123')));
      }
    }
    expect(() => VelaSubscriptionParser.parse('invalid token'),
        throwsFormatException);
    expect(() => VelaSubscriptionParser.parse('"subscription expired"'),
        throwsFormatException);
  });

  test('JSON string list and YAML list of share links are recognized', () {
    const link = 'trojan://pw@jp.example.test:443?security=tls#JP';
    final jsonList = jsonEncode([link]);
    final first = VelaSubscriptionParser.parse(jsonList);
    expect(first.nodes.single.name, 'JP');
    final yamlList = '- $link';
    final second = VelaSubscriptionParser.parse(yamlList);
    expect(second.nodes.single.name, 'JP');
  });
}
