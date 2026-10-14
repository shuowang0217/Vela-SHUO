import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/vela_world_cities.dart';

void main() {
  test('English node labels reflect specific city names', () {
    final fallback = VelaDemoNode.samples.first;
    expect(VelaWorldCityCatalog.resolve('JP Tokyo-01', fallback).label, 'TOKYO');
    expect(VelaWorldCityCatalog.resolve('JP Osaka-02', fallback).label, 'OSAKA');
    expect(VelaWorldCityCatalog.resolve('美国 纽约 01', fallback).label, 'NEW YORK');
    expect(VelaWorldCityCatalog.resolve('Hong Kong HK-01', fallback).label, 'HONG KONG');
    expect(VelaWorldCityCatalog.resolve('🇩🇪 Frankfurt', fallback).label, 'FRANKFURT');
  });

  test('selected city has plausible longitude and latitude', () {
    for (final city in VelaWorldCityCatalog.cityList) {
      expect(city.coordinate.dx, inInclusiveRange(-180, 180));
      expect(city.coordinate.dy, inInclusiveRange(-90, 90));
    }
  });
}
