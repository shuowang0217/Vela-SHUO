import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maritime notification art has gulls and sails, not GUI buttons',
      () {
    final script = File('scripts/prepare_oil_notification.py')
        .readAsStringSync();
    final art = File('assets/oil/ui/notification_maritime_reference.webp');
    expect(art.existsSync(), isTrue);
    expect(art.lengthSync(), greaterThan(4000));
    expect(art.openSync().readSync(4), [82, 73, 70, 70]); // RIFF / WebP
    expect(script, contains('notification_maritime_reference.webp'));
    expect(script, isNot(contains('oil_canvas.webp')));
    expect(script, isNot(contains('connection_plaque.png')));
    expect(script, contains('notification_oil_'));
  });
}
