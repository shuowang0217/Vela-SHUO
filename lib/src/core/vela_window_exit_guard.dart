import 'dart:async';

import 'package:window_manager/window_manager.dart';

import 'vela_core_controller.dart';
import 'vela_system_proxy.dart';

/// A Windows native-close barrier: never destroy the app window while the
/// old WinINet proxy could still point at our soon-to-be-terminated Mihomo.
class VelaWindowExitGuard extends WindowListener {
  VelaWindowExitGuard({required this.core, required this.proxy});

  final VelaCoreController core;
  final VelaSystemProxyManager proxy;
  Future<bool> Function()? shutdownConnection;
  bool _closing = false;

  @override
  void onWindowClose() {
    unawaited(closeSafely());
  }

  Future<bool> closeSafely() async {
    if (_closing) return false;
    _closing = true;
    try {
      final shutdown = shutdownConnection;
      final bool restored;
      if (shutdown != null) {
        restored = await shutdown();
      } else if (await proxy.disable()) {
        await core.stop();
        restored = true;
      } else {
        restored = false;
      }
      if (!restored) {
        // Keep the UI + live local endpoint available for the user to fix
        // Windows proxy restoration. This condition must NOT force-quit.
        return false;
      }
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      return true;
    } catch (_) {
      return false;
    } finally {
      _closing = false;
    }
  }
}
