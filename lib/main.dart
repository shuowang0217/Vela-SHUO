import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/network/flclash_windows_backend.dart';
import 'package:vela_shuo/src/network/flclash_android_backend.dart';
import 'package:vela_shuo/src/network/vela_flclash_core_adapter.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';
import 'package:vela_shuo/src/core/vela_window_exit_guard.dart';
import 'package:window_manager/window_manager.dart';
import 'package:vela_shuo/src/diagnostics/vela_diagnostics.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  final diagnostics = VelaDiagnostics();
  // Vela continues to own the ENTIRE Flutter app. The Windows network,
  // subscription and proxy engines now run exclusively inside FlClash Go.
  // Do not instantiate the legacy VelaNativeCoreRunner on Windows.
  final core = Platform.isWindows
      ? VelaFlClashCoreController(FlClashWindowsBackend())
      : Platform.isAndroid
          ? VelaFlClashCoreController(FlClashAndroidBackend())
          : VelaCoreController();
  final systemProxy = VelaSystemProxyManager();

  // Initialize the binding inside the same error zone as the application.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      // User exception messages and stack traces are intentionally never
      // written to the persistent diagnostic journal.
      diagnostics.record(VelaDiagnosticEvent.flutterError);
      if (kDebugMode) FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      diagnostics.record(VelaDiagnosticEvent.uncaughtError);
      return true; // The UI should remain usable when recovery is possible.
    };

    diagnostics.record(VelaDiagnosticEvent.appStarted);
    final settings = SettingsController(diagnostics: diagnostics);
    await settings.load();
    // Recover a previous app-owned proxy before any new core can start.
    if (Platform.isWindows) await systemProxy.recover();
    await core.initialize(); // Does not automatically start a proxy.
    VelaWindowExitGuard? exitGuard;
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      exitGuard = VelaWindowExitGuard(core: core, proxy: systemProxy);
      // Native window close will wait for proxy recovery + core termination.
      await windowManager.setPreventClose(true);
      windowManager.addListener(exitGuard);
    }
    runApp(VelaShuoApp(settings: settings, diagnostics: diagnostics,
      core: core, systemProxy: systemProxy, windowExitGuard: exitGuard));
  }, (error, stack) {
    diagnostics.record(VelaDiagnosticEvent.uncaughtError);
  });
}
