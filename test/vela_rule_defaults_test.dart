import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:vela_shuo/src/network/vela_rule_defaults.dart';

void main() {
  test('profiles without rules receive genuine Mihomo policy', () {
    const source = 'proxies: []\nproxy-groups: []\n';
    final normalized = VelaRuleDefaults.prepare(source);
    final parsed = loadYaml(normalized) as YamlMap;
    final rules = parsed['rules'] as YamlList;
    expect(rules, contains('IP-CIDR,192.168.0.0/16,DIRECT,no-resolve'));
    expect(rules, contains('DOMAIN-SUFFIX,cn,DIRECT'));
    expect(rules, contains('GEOIP,CN,DIRECT'));
    expect(rules.last, 'MATCH,GLOBAL');
    expect(VelaRuleDefaults.hasRules(normalized), true);
  });

  test('custom subscriptions keep rule order and user intent', () {
    const source = 'rules:\n  - DOMAIN-SUFFIX,example.com,DIRECT\n'
        '  - MATCH,DIRECT\n';
    expect(VelaRuleDefaults.prepare(source), source);
  });

  test('unknown input is rejected by Mihomo, not silently rewritten', () {
    const source = 'invalid: [ yaml';
    expect(VelaRuleDefaults.prepare(source), source);
  });
}
