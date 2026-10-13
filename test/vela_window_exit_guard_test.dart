import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';
import 'package:vela_shuo/src/core/vela_window_exit_guard.dart';

void main() {
  test('window X minimizes without disconnecting the active proxy', () async {
    final actions = <String>[];
    final guard = VelaWindowExitGuard(
      core: VelaCoreController(supported: false),
      proxy: VelaSystemProxyManager(supported: false),
      minimizeWindow: () async { actions.add('minimize'); },
      allowCloseWindow: () async { actions.add('allow-close'); },
      destroyWindow: () async { actions.add('destroy'); },
    )..shutdownConnection = () async {
        actions.add('shutdown');
        return true;
      };

    guard.onWindowClose();
    await Future<void>.delayed(Duration.zero);
    expect(actions, ['minimize']);
    // Explicit Exit, not the title-bar X, performs safe cleanup.
    expect(await guard.closeSafely(), true);
    expect(actions, ['minimize', 'shutdown', 'allow-close', 'destroy']);
  });

  test('failed proxy recovery prevents explicit program exit', () async {
    final actions = <String>[];
    final guard = VelaWindowExitGuard(
      core: VelaCoreController(supported: false),
      proxy: VelaSystemProxyManager(supported: false),
      minimizeWindow: () async { actions.add('minimize'); },
      allowCloseWindow: () async { actions.add('allow-close'); },
      destroyWindow: () async { actions.add('destroy'); },
    )..shutdownConnection = () async {
        actions.add('shutdown');
        return false;
      };
    expect(await guard.closeSafely(), false);
    expect(actions, ['shutdown']);
    // Even after a failed safe exit, the window close control still minimizes.
    expect(await guard.minimizeOnClose(), true);
    expect(actions, ['shutdown', 'minimize']);
  });

  test('repeated close events cannot start parallel window minimizations',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final guard = VelaWindowExitGuard(
      core: VelaCoreController(supported: false),
      proxy: VelaSystemProxyManager(supported: false),
      minimizeWindow: () async {
        calls++;
        await gate.future;
      },
    );
    final first = guard.minimizeOnClose();
    expect(await guard.minimizeOnClose(), false);
    expect(calls, 1);
    gate.complete();
    expect(await first, true);
  });
}
