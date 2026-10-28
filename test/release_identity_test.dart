import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/update/vela_update_service.dart';

void main() {
  test('1.10.1 beta exit IP preview has distinct binaries and signed app identity', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final generator = File('scripts/configure_android_vpn.py')
        .readAsStringSync();
    final workflow = File('.github/workflows/vela-exit-ip-preview.yml')
        .readAsStringSync();
    final stableWorkflow = File('.github/workflows/vela-host-flclash-core.yml')
        .readAsStringSync();
    final windows = File('scripts/configure_windows_product.py')
        .readAsStringSync();
    expect(pubspec, contains('version: 1.10.1-beta.1+59'));
    expect(generator, contains('applicationId = "com.shuowang.vela"'));
    expect(generator, contains('android:label="Vela"'));
    expect(generator, contains('signingConfigs.getByName("velaRelease")'));
    expect(workflow, contains('SHUO_SIGNING_PASSWORD'));
    expect(workflow, contains('shuo_signing.py restore'));
    final signer = File('scripts/finalize_android_signing.py')
        .readAsStringSync();
    expect(workflow, contains('scripts/finalize_android_signing.py'));
    expect(signer, contains(
        '3e8826e8aa48576ddfce7a9a2e78106a159c7be05dbb3b2f89eb60fb095ac9d9'));
    expect(generator, contains('keyAlias = "shuo-release"'));
    expect(workflow, contains('Vela-v1.10.1-beta.1-Android-arm64.apk'));
    expect(workflow, contains('Vela-v1.10.1-beta.1-Windows-x64.zip'));
    expect(workflow, contains("versionCode='59' versionName='1.10.1-beta.1'"));
    expect(workflow, isNot(contains('gh release create')));
    expect(stableWorkflow, contains('version: 1.10.0+58'));
    expect(stableWorkflow, contains('gh release create v1.10.0'));
    expect(workflow, contains('feature/v1.10.0-inline-exit-ip'));
    expect(windows, contains('set(BINARY_NAME "Vela")'));
    expect(VelaUpdateService.currentVersion, '1.10.1-beta.1');
  });

  test('update version comparison requires newer semantic release', () {
    expect(VelaUpdateService.isNewer('v1.5.1', '1.5.0'), isTrue);
    expect(VelaUpdateService.isNewer('v1.7.0', '1.5.0'), isTrue);
    expect(VelaUpdateService.isNewer('v1.5.0', '1.5.0'), isFalse);
    expect(VelaUpdateService.isNewer('v1.4.9', '1.5.0'), isFalse);
    expect(VelaUpdateService.isNewer('invalid', '1.5.0'), isFalse);
    expect(VelaUpdateService.isNewer('v1.10.1', '1.10.1-beta.1'),
        isTrue);
    expect(VelaUpdateService.isNewer('v1.10.1-beta.2', '1.10.1-beta.1'),
        isTrue);
    expect(VelaUpdateService.isNewer('v1.10.1-beta.1', '1.10.1'),
        isFalse);
    expect(VelaUpdateService.isNewer('v1.10.0', '1.10.1-beta.1'),
        isFalse);

  });
}
