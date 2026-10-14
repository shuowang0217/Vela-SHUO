
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/home/vela_reference_dashboard.dart';
import 'package:vela_shuo/src/home/vela_voyage_map.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';

void main() {
  testWidgets('layout 1536x1024 matches key design regions',
      (tester) async {
    tester.view.physicalSize = const Size(1536, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final core = VelaCoreController(supported: false);
    final subscription = VelaSubscriptionController(
        core: core, previewOnly: true);
    addTearDown(() {
      subscription.dispose();
      core.dispose();
    });
    const key = ValueKey('reference_preview_boundary');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: RepaintBoundary(key: key, child: Stack(children: [
        const Positioned.fill(child: VelaVoyageMap(
          connected: false, nodeName: null)),
        Positioned.fill(child: Row(children: [
          Container(
            width: 230,
            color: const Color(0x8B0A293F),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 35),
            child: const Text('⛵  Vela', style: TextStyle(
              color: Colors.white, fontSize: 24)),
          ),
          Expanded(child: VelaReferenceDashboard(
            subscription: subscription,
            openConfig: () {}, openNodes: () {},
          )),
        ])),
      ])),
    )));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('当前航线'), findsOneWidget);
    expect(find.text('连接信息'), findsOneWidget);
    expect(find.text('常用节点'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
