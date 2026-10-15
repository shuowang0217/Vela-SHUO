import 'package:yaml/yaml.dart';

/// Applies a conservative, documented split policy only when a user's Mihomo
/// YAML has NO usable rules. All user-provided rules remain authoritative.
/// Both Windows named-pipe and Android JNI import paths use this same code.
class VelaRuleDefaults {
  const VelaRuleDefaults._();

  static bool hasRules(String source) {
    try {
      final root = loadYaml(source);
      if (root is! YamlMap) return false;
      final rules = root['rules'];
      return rules is YamlList && rules.any(
          (line) => line is String && line.trim().isNotEmpty);
    } catch (_) {
      // Leave invalid/unsupported formats to Mihomo's native validator.
      return false;
    }
  }

  static String prepare(String source) {
    if (hasRules(source)) return source;
    try {
      final root = loadYaml(source);
      if (root is! YamlMap || root['rules'] != null) return source;
    } catch (_) {
      return source;
    }
    // GEOIP is evaluated by Mihomo's own geodata engine; local-address rules
    // prevent RFC1918 networks and localhost from leaving the machine.
    return '$source\n'
        'rules:\n'
        '  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve\n'
        '  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve\n'
        '  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve\n'
        '  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve\n'
        '  - DOMAIN-SUFFIX,cn,DIRECT\n'
        '  - GEOIP,CN,DIRECT,no-resolve\n'
        '  - MATCH,GLOBAL\n';
  }

  /// A source may deliberately choose another split policy. Do not silently
  /// rewrite MATCH,DIRECT or remote rule-providers in their custom rules.
  static String explanation(String source) => hasRules(source)
      ? '遵循机场配置的规则，未强制重写'
      : '使用默认分流：内网/国内直连，其他经 GLOBAL 节点';
}
