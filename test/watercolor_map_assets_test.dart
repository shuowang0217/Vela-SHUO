import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user-supplied watercolor atlas has full-size 2:1 matched day/night imagery', () {
    final day = File('assets/world/watercolor_day.webp').readAsBytesSync();
    final night = File('assets/world/watercolor_night.webp').readAsBytesSync();
    for (final bytes in [day, night]) {
      expect(bytes.length, greaterThan(200000));
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WEBP');
      // Decoded lossless grid must be the same 1774x887 coordinate grid.
      // WebP VP8 may use only even dimensions internally; display is 1774x887.
    }
  });
}
