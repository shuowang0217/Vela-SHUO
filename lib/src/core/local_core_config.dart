import 'dart:convert';

/// Deliberately narrow first real-core input: one local mixed/HTTP inbound.
/// No remote URLs or arbitrary system/TUN listeners are accepted in v0.2-a.
class VelaLocalCoreConfig {
  const VelaLocalCoreConfig({required this.localPort, required this.inboundType});

  final int localPort;
  final String inboundType;

  static const maxBytes = 2 * 1024 * 1024;

  /// Parse in memory, never echo or log the JSON (which can contain secrets).
  static VelaLocalCoreConfig parse(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('配置文件超过 2 MB 限制');
    }
    dynamic data;
    try {
      data = jsonDecode(source);
    } on FormatException {
      throw const FormatException('配置不是有效 JSON');
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('配置根节点必须是 JSON 对象');
    }
    final inbounds = data['inbounds'];
    final outbounds = data['outbounds'];
    if (inbounds is! List || inbounds.length != 1 ||
        outbounds is! List || outbounds.isEmpty) {
      throw const FormatException('此预览版要求恰好一个本地入站及至少一个出站');
    }
    final inbound = inbounds.single;
    if (inbound is! Map<String, dynamic>) {
      throw const FormatException('入站配置格式不正确');
    }
    final type = inbound['type'];
    final listen = inbound['listen'];
    final port = inbound['listen_port'];
    if (type != 'mixed' && type != 'http') {
      throw const FormatException('仅支持 HTTP 或 mixed 本地入站；TUN 尚未开放');
    }
    if (listen != '127.0.0.1') {
      throw const FormatException('为保护隐私，入站地址必须为 127.0.0.1');
    }
    if (port is! int || port < 1024 || port > 65535) {
      throw const FormatException('端口必须在 1024–65535 之间');
    }
    for (final item in outbounds) {
      if (item is! Map<String, dynamic> || item['type'] is! String) {
        throw const FormatException('出站配置格式不正确');
      }
    }
    // A JSON shape check is not a substitute for sing-box check.
    return VelaLocalCoreConfig(localPort: port, inboundType: type as String);
  }
}
