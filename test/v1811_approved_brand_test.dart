import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/brand/vela_selected_identity.dart';

void main() {
  testWidgets('user-approved icon and hand-painted VELA asset render',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: Column(children: [
        VelaSelectedIcon(size: 56),
        VelaSelectedWordmark(width: 198,height: 94),
      ]),
    )));
    await tester.pump();
    expect(find.byType(VelaSelectedIcon),findsOneWidget);
    expect(find.byType(VelaSelectedWordmark),findsOneWidget);
    expect(find.byType(Image),findsNWidgets(2));
  });
  test('one source artwork drives Android, Windows and Flutter branding', () {
    final icon=File('assets/brand/selected_oil_identity.webp');
    final image=File('assets/brand/vela_selected_icon.png');
    final handlettered=File('assets/brand/vela_selected_wordmark.png');
    expect(icon.existsSync(), isTrue);
    expect(icon.lengthSync(),greaterThan(4500));
    expect(image.existsSync(),isTrue);
    expect(handlettered.existsSync(),isTrue);
    expect(image.lengthSync(),greaterThan(10000));
    expect(handlettered.lengthSync(),greaterThan(10000));
    final native=File('scripts/generate_vela_brand_icons.py')
        .readAsStringSync();
    expect(native,contains('assets/brand/vela_selected_icon.png'));
    final workflow=File('.github/workflows/vela-host-flclash-core.yml')
        .readAsStringSync();
    expect('python3 scripts/prepare_selected_brand.py'
        .allMatches(workflow).length,2);
    expect(workflow,contains('python scripts/prepare_selected_brand.py'));
    final app=File('lib/src/app.dart').readAsStringSync();
    expect('VelaSelectedWordmark'.allMatches(app).length,3);
    expect(app,isNot(contains('VelaSailMark(')));
    final night=File('lib/src/home/world_atlas.dart').readAsStringSync();
    expect(night,contains('oil_map_night.webp'));
    final clouds=File('lib/src/home/vela_oil_scene.dart')
        .readAsStringSync();
    expect(clouds,contains('night_${cloud.file}.png'));
  });
}
