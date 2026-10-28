import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/update/vela_update_service.dart';

void main() {
  test('v1.11.0 stable has signed dual-platform binaries and gated publication', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final generator = File('scripts/configure_android_vpn.py').readAsStringSync();
    final workflow =
        File('.github/workflows/vela-v1.11.0-release.yml').readAsStringSync();
    final baseline =
        File('.github/workflows/vela-host-flclash-core.yml').readAsStringSync();
    final signer = File('scripts/finalize_android_signing.py')
        .readAsStringSync();
    final windows = File('scripts/configure_windows_product.py')
        .readAsStringSync();

    expect(pubspec, contains('version: 1.11.0+63'));
    expect(pubspec, contains('country_flags: ^4.1.2'));
    expect(File('lib/src/network/vela_exit_ip_indicator.dart').readAsStringSync(),
        contains('VelaOilFlagTexturePainter'));
    expect(generator, contains('applicationId = "com.shuowang.vela"'));
    expect(generator, contains('android:label="Vela"'));
    expect(generator, contains('signingConfigs.getByName("velaRelease")'));
    expect(generator, contains('keyAlias = "shuo-release"'));
    expect(workflow, contains('SHUO_SIGNING_PASSWORD'));
    expect(workflow, contains('shuo_signing.py restore'));
    expect(workflow, contains('scripts/finalize_android_signing.py'));
    expect(signer, contains(
        '3e8826e8aa48576ddfce7a9a2e78106a159c7be05dbb3b2f89eb60fb095ac9d9'));
    expect(workflow, contains('Vela-v1.11.0-Android-arm64.apk'));
    expect(workflow, contains('Vela-v1.11.0-Windows-x64.zip'));
    expect(workflow, contains("versionCode='63' versionName='1.11.0'"));
    expect(workflow, contains('branches: [release/v1.11.0]'));
    expect(workflow, contains("github.ref == 'refs/heads/release/v1.11.0'"));
    expect(workflow, contains('needs: [vela-ui, windows, android]'));
    expect(workflow, contains('gh release create v1.11.0'));
    expect(workflow, contains('--notes-file docs/RELEASE_v1.11.0.md'));
    expect(workflow, contains('--latest'));
    expect(baseline, contains('version: 1.10.0+58'));
    expect(baseline, contains('gh release create v1.10.0'));
    expect(windows, contains('set(BINARY_NAME "Vela")'));
    expect(VelaUpdateService.currentVersion, '1.11.0');
  });

  test('stable semantic update comparison is monotonic', () {
    expect(VelaUpdateService.isNewer('v1.11.0', '1.10.0'), isTrue);
    expect(VelaUpdateService.isNewer('v1.11.0', '1.10.1-beta.4'), isTrue);
    expect(VelaUpdateService.isNewer('v1.11.0', '1.11.0'), isFalse);
    expect(VelaUpdateService.isNewer('v1.10.1', '1.11.0'), isFalse);
    expect(VelaUpdateService.isNewer('v1.11.1', '1.11.0'), isTrue);
    expect(VelaUpdateService.isNewer('invalid', '1.11.0'), isFalse);
  });
}
