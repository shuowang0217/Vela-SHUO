import 'dart:async';

import 'package:window_manager/window_manager.dart';

import 'vela_core_controller.dart';
import 'vela_system_proxy.dart';

/// Windows window lifecycle guard.
///
/// Clicking the title-bar X minimizes Vela to the taskbar. It must NOT
/// terminate a running Go core or restore the system proxy. Only an explicit
/// "Exit application" action invokes closeSafely(), which restores the
/// previous WinINet state before the window may be destroyed.
class VelaWindowExitGuard extends WindowListener {
  VelaWindowExitGuard({
    required this.core,
    required this.proxy,
    Future<void> Function()? minimizeWindow,
    Future<void> Function()? allowCloseWindow,
    Future<void> Function()? destroyWindow,
  }) : _minimizeWindow = minimizeWindow ?? windowManager.minimize,
       _allowCloseWindow = allowCloseWindow ??
           (() => windowManager.setPreventClose(false)),
       _destroyWindow = destroyWindow ?? windowManager.destroy;

  final VelaCoreController core;
  final VelaSystemProxyManager proxy;
  final Future<void> Function() _minimizeWindow;
  final Future<void> Function() _allowCloseWindow;
  final Future<void> Function() _destroyWindow;
  Future<bool> Function()? shutdownConnection;
  bool _closing = false;
  bool _minimizing = false;

  @override
  void onWindowClose() {
    unawaited(minimizeOnClose());
  }

  /// Does not touch the connection, proxy journal, or core process.
  Future<bool> minimizeOnClose() async {
    if (_closing || _minimizing) return false;
    _minimizing = true;
    try {
      await _minimizeWindow();
      return true;
    } catch (_) {
      return false;
    } finally {
      _minimizing = false;
    }
  }

  /// Called only by the explicit Exit action, never by the window X button.
  /// Refuse to terminate when system proxy recovery cannot be confirmed.
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
        // Keep the UI + local endpoint running if recovery fails.
        return false;
      }
      await _allowCloseWindow();
      await _destroyWindow();
      return true;
    } catch (_) {
      return false;
    } finally {
      _closing = false;
    }
  }
}
