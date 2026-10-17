import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/brand/vela_glass_toast.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

void main() {
  testWidgets('glass toast floats at the top and replaces earlier notices',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => Scaffold(body: Center(child: FilledButton(
        onPressed: () => VelaGlassToast.show(context, '已保存配置'),
        child: const Text('显示通知'),
      ))),
    )));
    await tester.tap(find.text('显示通知'));
    await tester.pumpAndSettle();
    expect(find.text('已保存配置'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('vela_glass_toast'))).dy,
        lessThan(120));
    if (VelaThemeRuntime.oilPreview) {
      expect(find.byType(VelaWatercolorSurface), findsWidgets);
    } else {
      expect(find.byType(BackdropFilter), findsWidgets);
    }
    await tester.tap(find.text('显示通知'));
    await tester.pumpAndSettle();
    expect(find.text('已保存配置'), findsOneWidget);
    VelaGlassToast.dismiss();
    await tester.pump();
    expect(find.text('已保存配置'), findsNothing);
  });
}
