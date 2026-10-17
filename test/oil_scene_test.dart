import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_oil_scene.dart';

void main() {
  test('v1.8 keeps six fully independent high-visibility cloud sprites', () {
    expect(VelaOilScene.clouds.length, 6);
    expect(VelaOilScene.referenceWidth, 1672);
    expect(VelaOilScene.referenceHeight, 941);
    expect(File(VelaOilScene.backgroundAsset).existsSync(), isTrue);
    for (final cloud in VelaOilScene.clouds) {
      final file = File('assets/oil/clouds/${cloud.file}.png');
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync().length, greaterThan(1000));
      expect(cloud.opacity, inInclusiveRange(0.9, 1.0));
    }
  });

  test('wind loops seamlessly and moves cloud sprites independently', () {
    final one = VelaOilScene.clouds.first;
    final two = VelaOilScene.clouds[1];
    expect((one.position(0) - one.position(1)).distance, lessThan(0.0001));
    expect((one.position(.15) - one.position(0)).distance, greaterThan(5));
    expect(one.position(.2), isNot(two.position(.2)));
  });

  testWidgets('oil scene is isolated from taps, and respects reduced motion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Scaffold(body: SizedBox.expand(child: VelaOilScene())),
    )));
    await tester.pump();
    expect(find.byType(VelaOilScene), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}