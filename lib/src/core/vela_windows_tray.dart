import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide MenuItem;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'vela_connection_coordinator.dart';
import 'vela_window_exit_guard.dart';

/// A self-contained status icon; generated locally rather than downloading
/// remote icon files or depending on Flutter asset paths in Release builds.
class VelaTrayIconBuilder {
  static Future<Uint8List> icon({required bool connected}) async {
    const size = 32;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final background = Paint()
      ..color = connected
          ? const Color(0xFF209978) : const Color(0xFF687587)
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(16, 16), 14, background);
    final mark = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final path = Path();
    if (connected) {
      path.moveTo(9, 16);
      path.lineTo(14, 21);
      path.lineTo(23, 11);
    } else {
      path.moveTo(10, 16);
      path.lineTo(22, 16);
    }
    canvas.drawPath(path, mark);
    final image = await recorder.endRecording().toImage(size, size);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Cannot encode tray icon');
      final png = data.buffer.asUint8List();
      // Windows ICO file with a single 32x32 PNG entry.
      final header = ByteData(22)
        ..setUint16(0, 0, Endian.little)
        ..setUint16(2, 1, Endian.little)
        ..setUint16(4, 1, Endian.little)
        ..setUint8(6, size)
        ..setUint8(7, size)
        ..setUint8(8, 0)
        ..setUint8(9, 0)
        ..setUint16(10, 1, Endian.little)
        ..setUint16(12, 32, Endian.little)
        ..setUint32(14, png.length, Endian.little)
        ..setUint32(18, 22, Endian.little);
      return Uint8List.fromList([
        ...header.buffer.asUint8List(), ...png,
      ]);
    } finally {
      image.dispose();
    }
  }
}

/// Windows title-bar X hides to the notification area, while - minimizes
/// normally. The connection service remains alive until explicit Safe Exit.
class VelaWindowsTrayController with TrayListener {
  VelaWindowsTrayController(this.exitGuard);

  final VelaWindowExitGuard exitGuard;
  VelaConnectionCoordinator? _connection;
  bool _initialized = false;
  bool _busy = false;
  bool? _lastConnected;
  String? _offIcon;
  String? _onIcon;

  Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    try {
      final folder = Directory(
          '${Platform.environment['LOCALAPPDATA'] ??
              Directory.systemTemp.path}${Platform.pathSeparator}'
          'Vela-SHUO${Platform.pathSeparator}Tray');
      await folder.create(recursive: true);
      _offIcon = '${folder.path}${Platform.pathSeparator}proxy-off.ico';
      _onIcon = '${folder.path}${Platform.pathSeparator}proxy-on.ico';
      await File(_offIcon!).writeAsBytes(
          await VelaTrayIconBuilder.icon(connected: false), flush: true);
      await File(_onIcon!).writeAsBytes(
          await VelaTrayIconBuilder.icon(connected: true), flush: true);
      await trayManager.setIcon(_offIcon!);
      await trayManager.setToolTip('Vela v1.1.0 · 代理已关闭');
      trayManager.addListener(this);
      _initialized = true;
      exitGuard.hideToTray = hideWindow;
      await _updateState();
    } catch (_) {
      // Never hide a window if the Windows tray failed to initialize.
      _initialized = false;
      exitGuard.hideToTray = null;
    }
  }

  void attachConnection(VelaConnectionCoordinator connection) {
    if (identical(connection, _connection)) return;
    _connection?.removeListener(_onConnection);
    _connection = connection;
    connection.addListener(_onConnection);
    unawaited(_updateState());
  }

  void _onConnection() => unawaited(_updateState());

  Future<bool> hideWindow() async {
    if (!_initialized) return false;
    try {
      await windowManager.hide();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _updateState() async {
    if (!_initialized) return;
    final link = _connection;
    final active = link != null && link.proxy.active && link.core.isListening;
    // Icons only change when the real OS proxy state changes, never based on
    // an optimistic button click or an unverified "connected" animation.
    if (_lastConnected != active) {
      _lastConnected = active;
      await trayManager.setIcon(active ? _onIcon! : _offIcon!);
    }
    await trayManager.setToolTip(active
        ? 'Vela v1.1.0 · 系统代理已开启'
        : 'Vela v1.1.0 · 系统代理已关闭');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: '打开 Vela 窗口'),
      MenuItem.separator(),
      MenuItem(key: 'enable', label: '开启代理',
          disabled: _busy || link == null || link.busy ||
              link.proxy.active || !link.available),
      MenuItem(key: 'disable', label: '关闭代理',
          disabled: _busy || link == null || link.busy ||
              (!link.proxy.active && !link.core.isListening)),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '退出软件'),
    ]));
  }

  Future<void> _applyConnection(bool enable) async {
    final link = _connection;
    if (_busy || link == null || link.busy) return;
    _busy = true;
    await _updateState();
    try {
      if (enable) {
        if (link.available && !link.proxy.active) {
          // Explicit "Enable Proxy" context-menu action is user consent.
          // Reuse all existing connection verification and WinINet rollback.
          final success = await link.connect();
          if (!success) await showWindow();
        } else {
          await showWindow();
        }
      } else {
        if (link.proxy.active || link.core.isListening) {
          final success = await link.disconnect();
          if (!success) await showWindow();
        }
      }
    } finally {
      _busy = false;
      await _updateState();
    }
  }

  Future<void> _exit() async {
    if (_busy) return;
    _busy = true;
    try {
      // Safety barrier: if WinINet recovery fails, do NOT destroy the tray
      // or terminate the running local proxy endpoint.
      final ok = await exitGuard.closeSafely();
      if (!ok) await showWindow();
    } finally {
      _busy = false;
      await _updateState();
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(showWindow());

  @override
  void onTrayIconRightMouseDown() {
    // Windows tray_manager automatically shows the assigned right-click menu.
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'open':
        unawaited(showWindow());
      case 'enable':
        unawaited(_applyConnection(true));
      case 'disable':
        unawaited(_applyConnection(false));
      case 'exit':
        unawaited(_exit());
    }
  }

  Future<void> dispose() async {
    _connection?.removeListener(_onConnection);
    _connection = null;
    exitGuard.hideToTray = null;
    if (!_initialized) return;
    _initialized = false;
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
