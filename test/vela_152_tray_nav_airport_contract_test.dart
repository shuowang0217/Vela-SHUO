import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows tray has distinct real-state icons and Vela-only tooltip', () {
    final tray = File('lib/src/core/vela_windows_tray.dart')
        .readAsStringSync();
    final icons = File('scripts/generate_vela_brand_icons.py')
        .readAsStringSync();
    expect(tray, contains("'assets/tray/proxy_off.ico'"));
    expect(tray, contains("'assets/tray/proxy_on.ico'"));
    expect(tray, contains('link.proxy.active && link.core.isListening'));
    expect(tray, contains('setIcon(active ? _onIcon : _offIcon)'));
    expect(tray, contains("setToolTip('Vela')"));
    expect(tray, isNot(contains("Vela v1.3.0")));
    expect(icons, contains('ImageOps.grayscale'));
    expect(icons, contains('assets/brand/vela_selected_icon.png'));
    expect(icons, contains('gray.putalpha(image.getchannel(\"A\"))'));
  });

  test('dock toggles to Home on second click, for all function modules', () {
    final app = File('lib/src/app.dart').readAsStringSync();
    expect(app, contains('tab = i != 0 && tab == i ? 0 : i'));
    expect(app, contains("onTap: () => onNavigate(target)"));
  });

  test('empty airport name reads provider filename on both import paths', () {
    final adapter = File('lib/src/network/vela_flclash_subscription_adapter.dart')
        .readAsStringSync();
    final backend = File('lib/src/network/flclash_windows_backend.dart')
        .readAsStringSync();
    final source = File('lib/src/subscription/flclash_profile_downloader.dart')
        .readAsStringSync();
    expect(adapter, contains('VelaSubscriptionSuggestedName.displayName('));
    expect(adapter, contains('suggestedName: fetched.suggestedName'));
    expect(adapter, contains('suggestedName: backend.lastImportedSuggestedName'));
    expect(backend, contains('lastImportedSuggestedName = downloaded.suggestedName'));
    expect(source, contains("response.headers.value('content-disposition')"));
    expect(source, contains('VelaSubscriptionSuggestedName.fromContentDisposition'));
  });
}
