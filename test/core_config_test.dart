import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/local_core_config.dart';

const _valid = '''
{
  "inbounds": [{"type":"mixed", "listen":"127.0.0.1", "listen_port":20808}],
  "outbounds": [{"type":"direct", "tag":"direct"}]
}''';

void main() {
  test('strict localhost mixed inbound is recognized', () {
    final result = VelaLocalCoreConfig.parse(_valid);
    expect(result.localPort, 20808);
    expect(result.inboundType, 'mixed');
  });

  test('reject publicly reachable or omitted bind addresses', () {
    for (final listen in ['0.0.0.0', '::', '192.168.0.2']) {
      expect(
        () => VelaLocalCoreConfig.parse(_valid.replaceFirst(
          '127.0.0.1', listen,
        )),
        throwsFormatException,
      );
    }
    expect(() => VelaLocalCoreConfig.parse(
      _valid.replaceFirst('"listen":"127.0.0.1",', ''),
    ), throwsFormatException);
  });

  test('reject TUN, privileged port, duplicate inbounds or no outbound', () {
    expect(
      () => VelaLocalCoreConfig.parse(_valid.replaceFirst('mixed', 'tun')),
      throwsFormatException,
    );
    expect(
      () => VelaLocalCoreConfig.parse(_valid.replaceFirst('20808', '80')),
      throwsFormatException,
    );
    expect(
      () => VelaLocalCoreConfig.parse(
        _valid.replaceFirst('"inbounds": [', '"inbounds": [{},'),
      ),
      throwsFormatException,
    );
    expect(
      () => VelaLocalCoreConfig.parse(
        _valid.replaceFirst(
          '"outbounds": [{"type":"direct", "tag":"direct"}]',
          '"outbounds": []',
        ),
      ),
      throwsFormatException,
    );
  });

  test('reject non-JSON, scalar root and oversized payload', () {
    expect(() => VelaLocalCoreConfig.parse('{ not json'), throwsFormatException);
    expect(() => VelaLocalCoreConfig.parse('["a"]'), throwsFormatException);
    expect(
      () => VelaLocalCoreConfig.parse('x' * (VelaLocalCoreConfig.maxBytes + 1)),
      throwsFormatException,
    );
  });
}
