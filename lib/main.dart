import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/diagnostics/vela_diagnostics.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

void main() {
  final diagnostics = VelaDiagnostics();

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
    runApp(VelaShuoApp(settings: settings, diagnostics: diagnostics));
  }, (error, stack) {
    diagnostics.record(VelaDiagnosticEvent.uncaughtError);
  });
}
