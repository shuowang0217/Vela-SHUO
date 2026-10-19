import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/painted_ocean_route.dart';

void main() {
  test('painted ocean mask accepts LF and CRLF', () {
    final row = List<String>.filled(VelaPaintedOceanRoute.columns, '1').join();
    final lines = List<String>.filled(VelaPaintedOceanRoute.rows, row);
    expect(VelaPaintedOceanRoute.parseGrid(lines.join('\n') + '\n'), lines);
    expect(VelaPaintedOceanRoute.parseGrid(lines.join('\r\n') + '\r\n'), lines);
    expect(VelaPaintedOceanRoute.parseGrid(lines.join('\n')), lines);
  });

  test('bad masks cannot paint over land', () {
    final row = List<String>.filled(VelaPaintedOceanRoute.columns, '1').join();
    final lines = List<String>.filled(VelaPaintedOceanRoute.rows, row);
    expect(() => VelaPaintedOceanRoute.parseGrid(lines.take(67).join('\n')),
        throwsFormatException);
    lines[4] = row.substring(0, 119) + 'x';
    expect(() => VelaPaintedOceanRoute.parseGrid(lines.join('\r\n')),
        throwsFormatException);
  });

  test('generator creates LF bytes on Windows', () {
    final script = File('scripts/generate_painted_sea_grid.py').readAsStringSync();
    expect(script, contains('OUT.write_bytes('));
    expect(script, isNot(contains('OUT.write_text(')));
  });
}
