import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Vela passes airport rules unchanged to the pinned FlClash Go core', () {
    final dart = File('lib/src/network/flclash_windows_backend.dart')
        .readAsStringSync();
    final go = File('scripts/migration/flclash_native/vela_profile_windows.go')
        .readAsStringSync();

    expect(dart, contains("'content': raw"));
    expect(dart, isNot(contains("VelaRuleDefaults.prepare(raw)")));
    expect(go, contains('config.UnmarshalRawConfig([]byte(params.Content))'));
    expect(go, contains('raw.Mode = T.Rule'));
    // Pinned Mihomo has Rule yaml:"rules" vs json:"rule".
    // json.Marshal(raw) previously dropped the entire RULE table on reload.
    expect(go, contains('serialized, err := yaml.Marshal(raw)'));
    expect(go, isNot(contains('serialized, err := json.Marshal(raw)')));
    // These are the exact default baseline DNS values in FlClash's
    // PatchClashConfig / Dns model at the pinned upstream source SHA.
    // FlClash does not replace an airport's own enabled DNS section.
    expect(go, contains('if !raw.DNS.Enable {'));
    expect(go, contains('raw.DNS.Enable = true'));
    expect(go, contains('raw.DNS.EnhancedMode = constant.DNSFakeIP'));
    expect(go, contains('https://doh.pub/dns-query'));
    expect(go, contains('https://dns.alidns.com/dns-query'));
    expect(go, contains('raw.IPv6 = false'));
    expect(go, contains('raw.TCPConcurrent = true'));
  });

  test('Native FlClash selection and local proxy must not depend on 204 URLs', () {
    final core = File('lib/src/network/vela_flclash_core_adapter.dart')
        .readAsStringSync();
    final connection = File('lib/src/core/vela_connection_coordinator.dart')
        .readAsStringSync();
    final android = File('lib/src/android/vela_android_vpn.dart')
        .readAsStringSync();
    expect(core, contains('requiresRemoteProbeBeforeTakeover => false'));
    expect(connection, contains('core.requiresRemoteProbeBeforeTakeover'));
    expect(android, contains('final snapshot = await api.getProxies();'));
    expect(android, isNot(contains('if (await testConnectivity())')));
  });

  test('Android uses FlClash JNI + its TUN address/DNS and restores route mode', () {
    final adapter = File('scripts/migration/attach_flclash_android_core.py')
        .readAsStringSync();
    final service = File('native/android/VelaVpnService.kt')
        .readAsStringSync();
    expect(adapter, contains('import com.follow.clash.core.Core'));
    expect(adapter, contains('Core.quickSetup(initJson, selection)'));
    expect(adapter, contains('Core.invokeMethod(modeRequest.toString())'));
    expect(adapter, contains('return@invokeMethod'));
    expect(adapter, contains('address = "172.19.0.1/30"'));
    expect(adapter, contains('dns = "172.19.0.2"'));
    expect(service, contains('.addDnsServer("172.19.0.2")'));
    expect(service, contains('.setBlocking(false)'));
    expect(service, contains('VelaVpnState.report("connected")'));
    final subscriptions = File('lib/src/network/vela_flclash_subscription_adapter.dart')
        .readAsStringSync();
    final profile = File('lib/src/subscription/vela_profile_library.dart')
        .readAsStringSync();
    expect(subscriptions, contains("'selected-map': backend.selectedMap"));
    expect(profile, contains("'selectedMap': selectedMap"));
    expect(subscriptions, contains('_restoreProfileSelections(saved)'));
  });
}
