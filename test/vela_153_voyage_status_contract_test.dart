import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/vela_voyage_connection_label.dart';

void main() {
  test('voyage title is tied to confirmed connection and selected airport', () {
    expect(VelaVoyageConnectionLabel.headline(
        connected: false, busy: false, airportName: '星河机场'), '未起航');
    expect(VelaVoyageConnectionLabel.headline(
        connected: false, busy: true, airportName: '星河机场'), '正在起航');
    expect(VelaVoyageConnectionLabel.headline(
        connected: true, busy: false, airportName: '星河机场'),
        '星河机场 · 抵达港口');
    expect(VelaVoyageConnectionLabel.headline(
        connected: true, busy: false, airportName: ' '),
        'Vela · 抵达港口');
    expect(VelaVoyageConnectionLabel.headline(
        connected: true, busy: true, airportName: '星河机场'), '正在起航');
  });

  test('both actual connection panels use the same airport status language', () {
    final app = File('lib/src/app.dart').readAsStringSync();
    final labels = RegExp('VelaVoyageConnectionLabel\\.headline\\(')
        .allMatches(app).length;
    expect(labels, 2);
    expect(app, contains('.profileName'));
    expect(app, contains('desktop_connection_uptime'));
    expect(app, contains('mobile_connection_uptime'));
  });

  test('Windows CI signs only with independently provisioned publisher PFX',
      () {
    final workflow = File('.github/workflows/vela-host-flclash-core.yml')
        .readAsStringSync();
    final signer = File('scripts/sign_vela_windows.ps1').readAsStringSync();
    expect(workflow, contains('scripts/sign_vela_windows.ps1'));
    expect(workflow, contains('secrets.VELA_WINDOWS_CODESIGN_PFX_B64'));
    expect(workflow, contains('secrets.VELA_WINDOWS_CODESIGN_PASSWORD'));
    expect(signer, contains('Get-AuthenticodeSignature'));
    expect(signer, contains("signature.Status -ne 'Valid'"));
    expect(signer, contains('Authenticode signing not configured'));
    expect(signer, contains('Remove-Item -LiteralPath $pfx -Force'));
  });
}
