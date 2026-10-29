import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';
import 'package:vela_shuo/src/network/vela_exit_ip_monitor.dart';
import 'package:vela_shuo/src/network/vela_network_diagnostics.dart';

class _DiagnosticProbe extends VelaExitIpProbe {
  _DiagnosticProbe() : super(FlClashCoreApi(_UnusedTransport()));
  final completers = <Completer<VelaExitIpInfo?>>[];
  @override
  Future<VelaExitIpInfo?> lookup() {
    final completer = Completer<VelaExitIpInfo?>();
    completers.add(completer);
    return completer.future;
  }
}

class _UnusedTransport implements FlClashCoreTransport {
  @override
  Future<String?> invoke(String requestJson) =>
      Future<String?>.value(null);
}

void main() {
  testWidgets('network diagnosis shows status and real route only in settings',
      (tester) async {
    final probe = _DiagnosticProbe();
    final monitor = VelaExitIpMonitor(
      probe: probe,
      interval: const Duration(days: 1),
      connectionSettle: Duration.zero,
      initialRetries: const [],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: VelaNetworkDiagnostics(monitor: monitor))),
    ));
    expect(find.text('网络诊断'), findsOneWidget);
    expect(find.text('未连接'), findsWidgets);
    expect(find.text('系统 DNS'), findsOneWidget);
    expect(find.text('内核 HTTPS'), findsOneWidget);
    expect(find.text('尚未单独测试'), findsNWidgets(2));
    monitor.sync(true, 'node-a', mode: 'rule');
    await tester.pump();
    probe.completers.first.complete(const VelaExitIpInfo(
      address: '203.0.113.44',
      countryCode: 'JP',
      chains: ['JP-AWS', 'GLOBAL'],
      coreEpoch: 9,
      picksVersion: 6,
      source: VelaExitIpProbe.cloudflare,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(monitor.info?.chains, ['JP-AWS', 'GLOBAL']);
    expect(find.text('JP-AWS → GLOBAL'), findsOneWidget);
    expect(find.text('核心 9 / 选择 6'), findsOneWidget);
    expect(find.text('已获得内核真实路由链'), findsOneWidget);
    monitor.dispose();
  });
}
