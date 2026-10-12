import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/stellar/vela_stellar_import_dialog.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

class _ImportFake extends VelaSubscriptionController {
  _ImportFake() : super(core: VelaCoreController(supported: false));
  bool accept = true;
  String? requestedUrl;

  @override
  Future<bool> importFromUrl(String url) async {
    requestedUrl = url;
    return accept;
  }

  @override
  String? get error => '订阅验证失败，请检查 URL';
}

void main() {
  testWidgets('compact Vela import dialog automatically closes on successful URL',
      (tester) async {
    VelaThemeRuntime.select(
      VelaPalette.byId('mint'), Brightness.light);
    final fake = _ImportFake();
    addTearDown(fake.dispose);
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await showDialog<bool>(
            context: context,
            builder: (_) => VelaStellarImportDialog(controller: fake),
          );
        },
        child: const Text('打开导入'),
      )),
    )));
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stellar_import_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('stellar_import_name')), findsOneWidget);
    expect(find.byKey(const ValueKey('stellar_import_url')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('stellar_import_name')), '我的航线');
    await tester.enterText(
        find.byKey(const ValueKey('stellar_import_url')),
        'https://subscribe.example.test/config?token=private');
    await tester.tap(find.byKey(const ValueKey('stellar_import_submit')));
    await tester.pumpAndSettle();
    expect(fake.requestedUrl,
        'https://subscribe.example.test/config?token=private');
    expect(find.byKey(const ValueKey('stellar_import_dialog')), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('failed import keeps the same popup and URL for correction',
      (tester) async {
    VelaThemeRuntime.select(
      VelaPalette.byId('ocean'), Brightness.dark);
    final fake = _ImportFake()..accept = false;
    addTearDown(fake.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => VelaStellarImportDialog(controller: fake)),
        child: const Text('打开导入'),
      )),
    )));
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('stellar_import_url')),
        'https://subscribe.example.test/profile');
    await tester.tap(find.byKey(const ValueKey('stellar_import_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stellar_import_dialog')), findsOneWidget);
    expect(find.text('订阅验证失败，请检查 URL'), findsOneWidget);
    expect(find.text('https://subscribe.example.test/profile'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stellar_import_dialog')), findsNothing);
  });
}
