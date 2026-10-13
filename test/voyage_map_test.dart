import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_voyage_map.dart';

void main() {
  group('maritime destination mapping', () {
    test('Japanese and Korean airport nodes use target coastal waters', () {
      final japan = VelaVoyageTarget.fromNodeName('🇯🇵 日本 东京 01');
      expect(japan, isNotNull);
      expect(japan!.label, '日本近海');
      expect(japan.latitude, closeTo(35.3, .01));
      expect(VelaVoyageTarget.fromNodeName('韩国 首尔 02')!.label,
          '韩国近海');
    });

    test('Singapore, US and Europe use distinct maritime targets', () {
      final singapore = VelaVoyageTarget.fromNodeName('SG-01 Singapore')!;
      final america = VelaVoyageTarget.fromNodeName('US-LA 低延迟')!;
      final europe = VelaVoyageTarget.fromNodeName('英国 London VIP')!;
      expect(singapore.longitude, closeTo(103.9, .1));
      expect(america.longitude, lessThan(0));
      expect(europe.label, '英国近海');
    });

    test('unknown server names never invent a real destination', () {
      expect(VelaVoyageTarget.fromNodeName('专线节点 1'), isNull);
      expect(VelaVoyageTarget.fromNodeName(''), isNull);
      expect(VelaVoyageTarget.fromNodeName(null), isNull);
    });
  });
}
