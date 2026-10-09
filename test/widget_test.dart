import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';

void main() {
  test('Vela-SHUO demo begins disconnected and selects nodes without traffic', () {
    final demo = VelaDemoController();
    expect(demo.phase, VelaPhase.idle);
    expect(demo.isConnected, false);
    demo.selectNode(VelaDemoNode.samples[2]);
    expect(demo.selected.id, 'us');
    expect(demo.phase, VelaPhase.idle);
    demo.connect();
    expect(demo.phase, VelaPhase.connecting);
    demo.disconnect();
    expect(demo.phase, VelaPhase.idle);
    demo.dispose();
  });

  test('smart flags are UI-only preferences in the prototype', () {
    final demo = VelaDemoController();
    demo.setSmart(false);
    demo.setProtection(false);
    expect(demo.smartEnabled, false);
    expect(demo.protectConnections, false);
    expect(demo.isConnected, false);
    demo.dispose();
  });
}
