import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/update/vela_update_service.dart';

void main() {
  test('v1.11.3 stable build 69 has signed dual-platform provenance', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final generator = File('scripts/configure_android_vpn.py')
        .readAsStringSync();
    final release = File('.github/workflows/vela-v1.11.3-release.yml')
        .readAsStringSync();
    final previous = File('.github/workflows/vela-v1.11.2-release.yml')
        .readAsStringSync();
    final notes = File('docs/releases/v1.11.3.md').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, contains('version: 1.11.3+69'));
    expect(VelaUpdateService.currentVersion, '1.11.3');
    expect(release, contains('branches: [release/v1.11.3]'));
    expect(release, contains("versionCode='69' versionName='1.11.3'"));
    expect(release, contains('Vela-v1.11.3-Windows-x64.zip'));
    expect(release, contains('Vela-v1.11.3-Android-arm64.apk'));
    expect(release, contains('SHA256-Windows.txt'));
    expect(release, contains('SHA256-Android.txt'));
    expect(release, contains('needs: [vela-ui, windows, android]'));
    expect(release, contains('scripts/finalize_android_signing.py'));
    expect(release, contains(r'gh release create "$tag"'));
    expect(release, contains('--latest'));
    expect(release, contains('docs/releases/v1.11.3.md'));
    expect(release, contains('SHUO_SIGNING_PASSWORD'));
    expect(release, contains("test \"\$(grep '^version:' pubspec.yaml)\" = \"version: 1.11.3+69\""));
    expect(generator, contains('applicationId = "com.shuowang.vela"'));
    expect(generator, contains('signingConfigs.getByName("velaRelease")'));
    expect(notes, contains('1.11.3+69'));
    expect(readme, contains('正式版 1.11.3'));
    // Past releases keep their original binaries and immutable workflow.
    expect(previous, contains('branches: [release/v1.11.2]'));
    expect(previous, contains('Vela-v1.11.2-Android-arm64.apk'));
  });

  test('stable 1.11.3 is newer than 1.11.2 and its test build', () {
    expect(VelaUpdateService.isNewer('v1.11.3', '1.11.2'), isTrue);
    expect(VelaUpdateService.isNewer('v1.11.3', '1.11.2+68'), isTrue);
    expect(VelaUpdateService.isNewer('v1.11.2', '1.11.3'), isFalse);
    expect(VelaUpdateService.isNewer('v1.11.2', '1.11.2-beta.3'), isTrue);
  });
}
