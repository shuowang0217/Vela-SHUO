import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_oil_scene.dart';

void main() {
  test('Android oil homepage has its own painted header and controls', () {
    final source = File('lib/src/app.dart').readAsStringSync();
    expect(source, contains("ValueKey('mobile_oil_masthead')"));
    expect(source, contains('航海油画  ·  v1.8.0'));
    expect(source, contains("ValueKey('mobile_oil_status')"));
    expect(source, contains('sigmaX: 10'));
  });

  test('georeferenced Android oil map is crisp instead of blurred', () {
    final atlas = File('lib/src/home/world_atlas.dart').readAsStringSync();
    final pipeline = File('scripts/prepare_oil_atlas.py').readAsStringSync();
    expect(atlas, contains('VelaThemeRuntime.oilPreview ? 0 : 16'));
    expect(pipeline, contains('ImageFilter.ModeFilter(7)'));
    expect(pipeline, contains('for i in range(102000)'));
    expect(pipeline, contains('base.paste(base.crop((0,0,1,h)),(w-1,0))'));
  });

  testWidgets('portrait cloud sprites are all partly visible and detached',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VelaOilScene()),
    ));
    await tester.pump();
    for (final cloud in VelaOilScene.clouds) {
      final target = find.byKey(ValueKey('oil_cloud_${cloud.file}'));
      expect(target, findsOneWidget);
      final rect = tester.getRect(target);
      expect(rect.left, lessThan(390));
      expect(rect.right, greaterThan(0));
      expect(rect.top, lessThan(844));
      expect(rect.bottom, greaterThan(0));
    }
  });
}
