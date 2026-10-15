import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/vela_rule_defaults.dart';

void main() {
  test('rule-less profiles are passed to FlClash/Mihomo unchanged', () {
    const source = 'proxies: []\nproxy-groups: []\n';
    expect(VelaRuleDefaults.prepare(source), source);
    expect(VelaRuleDefaults.hasRules(source), false);
    expect(VelaRuleDefaults.explanation(source), contains('不自动补写'));
  });

  test('custom subscriptions keep every upstream rule in the same order', () {
    const source = 'rules:\n  - DOMAIN-SUFFIX,example.com,DIRECT\n'
        '  - MATCH,DIRECT\n';
    expect(VelaRuleDefaults.prepare(source), source);
    expect(VelaRuleDefaults.hasRules(source), true);
  });

  test('invalid YAML is forwarded to Mihomo native validation', () {
    const source = 'invalid: [ yaml';
    expect(VelaRuleDefaults.prepare(source), source);
  });
}
