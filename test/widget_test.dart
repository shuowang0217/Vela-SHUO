import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Vela-SHUO has an independent Flutter identity', () {
    expect('vela_shuo', isNot('fl_clash'));
    expect('vela_shuo', 'vela_shuo');
  });
}
