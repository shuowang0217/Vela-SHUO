import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/local_core_config.dart';

const _valid = '''
{"mixed-port":20808,"bind-address":"127.0.0.1","allow-lan":false,
"mode":"rule","ipv6":false,"proxies":[],"proxy-groups":[],
"rules":["MATCH,DIRECT"]}
''';

void main() {
  test('strict loopback mixed profile is accepted', () {
    final config = VelaLocalCoreConfig.parse(_valid);
    expect(config.localPort, 20808);
    expect(config.inboundType, 'mixed');
  });

  test('public listener, LAN access and TUN are rejected', () {
    for (final address in ['0.0.0.0', '::', '192.168.0.2']) {
      expect(() => VelaLocalCoreConfig.parse(
        _valid.replaceFirst('127.0.0.1', address),
      ), throwsFormatException);
    }
    expect(() => VelaLocalCoreConfig.parse(
      _valid.replaceFirst('"allow-lan":false', '"allow-lan":true'),
    ), throwsFormatException);
    expect(() => VelaLocalCoreConfig.parse(
      _valid.replaceFirst('"mixed-port":20808', '"mixed-port":80'),
    ), throwsFormatException);
    expect(() => VelaLocalCoreConfig.parse(
      _valid.replaceFirst('"mode":"rule"', '"tun":{"enable":true},"mode":"rule"'),
    ), throwsFormatException);
  });

  test('missing listener, invalid rules and unauthorized API are rejected', () {
    expect(() => VelaLocalCoreConfig.parse(
      _valid.replaceFirst('"bind-address":"127.0.0.1",', ''),
    ), throwsFormatException);
    expect(() => VelaLocalCoreConfig.parse(
      _valid.replaceFirst('MATCH,DIRECT', 'MATCH,REJECT'),
    ), throwsFormatException);
    expect(() => VelaLocalCoreConfig.parse(
      _valid.replaceFirst('"mode":"rule"', '"external-controller":"0.0.0.0:9000","mode":"rule"'),
    ), throwsFormatException);
  });

  test('invalid JSON, scalar root and oversized files are rejected', () {
    expect(() => VelaLocalCoreConfig.parse('{ not json'), throwsFormatException);
    expect(() => VelaLocalCoreConfig.parse('["a"]'), throwsFormatException);
    expect(() => VelaLocalCoreConfig.parse('x' * (VelaLocalCoreConfig.maxBytes + 1)), throwsFormatException);
  });
}
