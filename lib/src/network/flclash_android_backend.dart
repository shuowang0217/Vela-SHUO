import 'dart:io';

import 'package:flutter/services.dart';

import 'flclash_core_api.dart';
import 'flclash_windows_backend.dart';

/// Android uses exactly the same FlClash Go profile import / node APIs as
/// Windows, but the underlying transport is the original FlClash JNI core.
/// No Vela protocol parser or second Android network stack is involved.
class FlClashAndroidBackend extends FlClashWindowsBackend {
  FlClashAndroidBackend()
      : super(transport: const FlClashAndroidTransport());

  static const _channel = MethodChannel('vela_shuo/android_vpn');

  @override
  Future<void> initialize() async {
    if (ready) return;
    if (!Platform.isAndroid) {
      throw UnsupportedError('FlClash JNI backend is Android only');
    }
    final home = await _channel.invokeMethod<String>('coreHomeDir');
    if (home == null || home.isEmpty) {
      throw StateError('Android native core directory unavailable');
    }
    if (!await api.initialize(home, androidApiLevel: 29)) {
      throw StateError('FlClash JNI core initialization failed');
    }
    ready = true;
  }

  /// VpnService is the ONLY party that starts/stops Android TUN. A Flutter
  /// node select or download never opens listeners or takes VPN permission.
  @override
  Future<void> start() async {
    throw UnsupportedError('Android TUN must start from VpnService');
  }

  @override
  Future<void> stop() async {
    internetVerified = false;
    listenerStarted = false;
  }

  @override
  Future<void> shutdown() async {
    if (ready) {
      try {
        await api.shutdown();
      } catch (_) {}
    }
    ready = false;
  }
}
