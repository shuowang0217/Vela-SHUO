import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/network/vela_flclash_core_adapter.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

class _RoutingTransport implements FlClashCoreTransport {
  final modes = <String>[];
  @override
  Future<String?> invoke(String requestJson) async {
    final req = jsonDecode(requestJson) as Map<String, dynamic>;
    if (req['method'] == 'updateConfig') {
      final args = req['arguments'] as Map<String, dynamic>;
      modes.add(args['mode'] as String);
      return jsonEncode({'id': req['id'], 'result': ''});
    }
    throw StateError('Unexpected native call ${req['method']}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop home owns native route selector, proxy page does not',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final transport = _RoutingTransport();
    final backend = FlClashWindowsBackend(transport: transport);
    backend.imported = true;
    await tester.pumpWidget(VelaShuoApp(
      settings: SettingsController(),
      core: VelaFlClashCoreController(backend),
    ));
    await tester.pump();
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    expect(find.byKey(const ValueKey('voyage_speed_panel')), findsOneWidget);
    expect(find.text('风速 · 上传'), findsOneWidget);
    expect(find.text('航速 · 下载'), findsOneWidget);
    expect(find.byKey(const ValueKey('home_routing_selector')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home_routing_open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home_routing_selector')), findsOneWidget);
    expect(find.text('航线模式'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('routing_mode_rule')));
    await tester.pump();
    expect(transport.modes, contains('rule'));
    // Tap outside the modal; there is no AppBar back arrow in this dialog.
    await tester.tapAt(const Offset(12, 450));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav_1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('home_routing_selector')), findsNothing);
    expect(find.byKey(const ValueKey('routing_mode_rule')), findsNothing);
    expect(find.byType(VelaWorldAtlas), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
