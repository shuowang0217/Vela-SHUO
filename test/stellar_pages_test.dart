import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/stellar/stellar_design.dart';
import 'package:vela_shuo/src/stellar/vela_stellar_config_page.dart';
import 'package:vela_shuo/src/stellar/vela_stellar_proxy_page.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

void main() {
  testWidgets('stellar proxy screen uses current palette and offers real import',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final demo = VelaDemoController();
    addTearDown(demo.dispose);
    VelaThemeRuntime.select(
        VelaPalette.byId('mint'), Brightness.light);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VelaStellarProxyPage(
        demo: demo,
        openConfig: () {},
      )),
    ));
    expect(find.text('全球加速'), findsOneWidget);
    expect(find.text('航线尚未载入'), findsOneWidget);
    expect(find.byType(StellarCompassGlyph), findsWidgets);
    expect(find.byKey(const ValueKey('stellar_open_config')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('stellar config never fabricates saved profiles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(470, 790));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final demo = VelaDemoController();
    addTearDown(demo.dispose);
    VelaThemeRuntime.select(
        VelaPalette.byId('ocean'), Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VelaStellarConfigPage(
        demo: demo,
        core: null,
      )),
    ));
    expect(find.text('配置管理'), findsOneWidget);
    expect(find.text('尚未添加航线配置'), findsOneWidget);
    expect(find.byType(StellarCompassGlyph), findsWidgets);
    expect(find.byKey(const ValueKey('stellar_add_profile')), findsOneWidget);
  });

  test('existing eight palettes remain unchanged', () {
    expect(VelaPalette.all.length, 9);
    expect(VelaPalette.all.skip(1).map((palette) => palette.id).toList(),
        ['mint', 'navy', 'peach', 'pink', 'sand',
         'rose', 'lavender', 'ocean']);
  });
}
