import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';

const sample = '''
proxies:
  - name: Tokyo
    type: ss
    server: jp.example.test
    port: 443
    cipher: aes-128-gcm
    password: fixture-secret
''';

void main() {
  test('Android generates Mihomo VPN TUN DNS with no exposed REST API',
      () async {
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(core: core, previewOnly: true);
    expect(await sub.importFromText(sample), true);
    expect(sub.androidVpnProfile, isNull);
    expect(await sub.selectNode(0), true);
    final source = sub.androidVpnProfile;
    expect(source, isNotNull);
    final json = jsonDecode(source!) as Map<String, dynamic>;
    expect(json.containsKey('external-controller'), false);
    expect(json.containsKey('secret'), false);
    expect(json['mixed-port'], 0);
    expect(json['bind-address'], '127.0.0.1');
    expect(json['ipv6'], false);
    final dns = json['dns'] as Map<String, dynamic>;
    expect(dns['enable'], true);
    expect(dns['enhanced-mode'], 'fake-ip');
    expect(dns['fake-ip-range'], '198.18.0.1/16');
    expect(json['rules'], ['MATCH,VELA_SELECT']);
    expect(json['proxies'], hasLength(1));
    expect(core.isListening, false);
    expect(core.hasCore, false);
    sub.dispose();
    core.dispose();
  });

  test('normal Windows subscription does not expose Android VPN profile',
      () async {
    final core = VelaCoreController(supported: false);
    final sub = VelaSubscriptionController(core: core);
    expect(await sub.importFromText(sample), true);
    expect(sub.androidVpnProfile, isNull);
    sub.dispose();
    core.dispose();
  });
}
