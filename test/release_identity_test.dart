import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/update/vela_update_service.dart';

void main() {
  test('v1.11.1 build 64 is isolated from the stable publishing workflow', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final generator = File('scripts/configure_android_vpn.py').readAsStringSync();
    final preview =
        File('.github/workflows/vela-v1.11.1-preview.yml').readAsStringSync();
    final stable =
        File('.github/workflows/vela-v1.11.0-release.yml').readAsStringSync();
    expect(pubspec, contains('version: 1.11.1+64'));
    expect(generator, contains('applicationId = "com.shuowang.vela"'));
    expect(generator, contains('signingConfigs.getByName("velaRelease")'));
    expect(preview, contains('feature/v1.11.1-stability'));
    expect(preview, contains("versionCode='64' versionName='1.11.1'"));
    expect(preview, contains('SHUO_SIGNING_PASSWORD'));
    expect(preview, contains('scripts/finalize_android_signing.py'));
    expect(preview, contains('Vela-v1.11.1-Windows-x64.zip'));
    expect(preview, contains('Vela-v1.11.1-Android-arm64.apk'));
    expect(preview, isNot(contains('gh release create')));
    expect(stable, contains('gh release create v1.11.0'));
    expect(stable, contains('version: 1.11.0+63'));
    expect(VelaUpdateService.currentVersion, '1.11.1');
  });

  test('patch releases compare correctly', () {
    expect(VelaUpdateService.isNewer('v1.11.1', '1.11.0'), isTrue);
    expect(VelaUpdateService.isNewer('v1.11.1', '1.11.1'), isFalse);
    expect(VelaUpdateService.isNewer('v1.12.0', '1.11.1'), isTrue);
    expect(VelaUpdateService.isNewer('v1.11.0', '1.11.1'), isFalse);
  });
}
