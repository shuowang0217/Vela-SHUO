import 'package:yaml/yaml.dart';

/// FlClash parity: Mihomo is authoritative for all user-supplied rules.
/// Never invent CN/DIRECT/MATCH rules or change rule order during import.
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
      return false;
    }
  }

  /// Exact pass-through: same config the FlClash native core sees.
  static String prepare(String source) => source;

  static String explanation(String source) => hasRules(source)
      ? '按机场原始规则及 Mihomo 策略组执行'
      : '机场未提供规则，按 Mihomo 默认行为执行；不自动补写分流策略';
}
