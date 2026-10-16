import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows and Android share the refined georeferenced day/night art', () {
    final atlas = File('lib/src/home/world_atlas.dart').readAsStringSync();
    final pipeline = File('scripts/prepare_watercolor_atlas.py').readAsStringSync();
    final workflow =
        File('.github/workflows/vela-host-flclash-core.yml').readAsStringSync();

    expect(atlas, contains('assets/world/watercolor_day.webp'));
    expect(atlas, contains('assets/world/watercolor_night.webp'));
    expect(pipeline, contains('def polish_day(image):'));
    expect(pipeline, contains('def polish_night(image):'));
    expect(pipeline, contains('ImageOps.colorize('));
    expect(pipeline, contains('night_with_lights = blend_city_lights(night_base)'));
    expect(pipeline, contains('ImageChops.difference(night_with_lights, night_base)'));
    expect(pipeline, contains('assets/earth/earth_night_lights.png'));
    expect(pipeline, contains('blend_wrap_seam(polish_day(day))'));
    expect(pipeline, contains('blend_wrap_seam(night_with_lights)'));
    // Both native jobs and the UI test job prepare the same source files.
    expect('python3 scripts/prepare_watercolor_atlas.py'.allMatches(workflow).length,
        greaterThanOrEqualTo(2));
    expect(workflow, contains('python scripts/prepare_watercolor_atlas.py'));
    expect(workflow, contains('Vela-v1.5.3-Android-arm64'));
    expect(workflow, contains('Vela-v1.5.3-Windows-x64'));
  });
}
