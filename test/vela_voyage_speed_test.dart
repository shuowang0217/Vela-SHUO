import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_voyage_speed.dart';

void main() {
  test('unknown rates display placeholder', () {
    expect(VelaVoyageSpeed.format(null), ('—', ''));
    expect(VelaVoyageSpeed.format(-1), ('—', ''));
    expect(VelaVoyageSpeed.format(double.nan), ('—', ''));
  });
  test('measured byte rates adapt units without rounding ambiguity', () {
    expect(VelaVoyageSpeed.format(0), ('0', 'B/s'));
    expect(VelaVoyageSpeed.format(1023), ('1023', 'B/s'));
    expect(VelaVoyageSpeed.format(1024), ('1', 'KB/s'));
    expect(VelaVoyageSpeed.format(1536), ('1.5', 'KB/s'));
    expect(VelaVoyageSpeed.format(1024 * 1024), ('1', 'MB/s'));
    expect(VelaVoyageSpeed.format(12.5 * 1024 * 1024), ('12.5', 'MB/s'));
    expect(VelaVoyageSpeed.format(100 * 1024 * 1024), ('100', 'MB/s'));
    expect(VelaVoyageSpeed.format(1024 * 1024 * 1024), ('1', 'GB/s'));
  });
}
