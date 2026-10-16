// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vela_shuo/src/update/vela_update_service.dart';
import 'package:vela_shuo/src/diagnostics/vela_diagnostics.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';
import 'package:vela_shuo/src/core/vela_window_exit_guard.dart';
import 'package:vela_shuo/src/core/vela_windows_tray.dart';
import 'package:vela_shuo/src/core/vela_connection_coordinator.dart';
import 'package:vela_shuo/src/core/vela_session_time.dart';
import 'package:vela_shuo/src/network/vela_flclash_core_adapter.dart';
import 'package:vela_shuo/src/network/vela_flclash_subscription_adapter.dart';
import 'package:vela_shuo/src/network/vela_routing_mode.dart';
import 'package:vela_shuo/src/network/flclash_go_node_probe.dart';
import 'package:vela_shuo/src/android/vela_android_vpn.dart';
import 'package:vela_shuo/src/traffic/vela_traffic_monitor.dart';
import 'package:vela_shuo/src/smart/vela_node_probe.dart';
import 'package:vela_shuo/src/smart/vela_smart_controller.dart';
import 'package:vela_shuo/src/smart/vela_smart_panel.dart';
import 'package:vela_shuo/src/core/vela_core_settings_card.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';
import 'package:vela_shuo/src/home/vela_voyage_speed.dart';
import 'package:vela_shuo/src/brand/vela_sail_mark.dart';
import 'package:vela_shuo/src/brand/vela_watercolor_chrome.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';
import 'package:vela_shuo/src/stellar/vela_stellar_proxy_page.dart';
import 'package:vela_shuo/src/stellar/vela_routing_mode_selector.dart';
import 'package:vela_shuo/src/stellar/vela_stellar_config_page.dart';

Color get _panel => VelaThemeRuntime.active.surface;
Color get _line => VelaThemeRuntime.active.line;
Color get _blue => VelaThemeRuntime.active.accent;
Color get _muted => VelaThemeRuntime.active.muted;
Color get _mint => VelaThemeRuntime.active.accentSoft;
Color get _foreground => VelaThemeRuntime.active.text;

/// Approved Vela-SHUO home-screen brand line. Keep this as the one source.
const velaBrandTagline = '一帆越洋，尽览四方。';

class VelaShuoApp extends StatelessWidget {
  const VelaShuoApp({
    super.key,
    required this.settings,
    this.diagnostics,
    this.core,
    this.systemProxy,
    this.windowExitGuard,
    this.windowsTray,
  });
  final SettingsController settings;
  final VelaDiagnostics? diagnostics;
  final VelaCoreController? core;
  final VelaSystemProxyManager? systemProxy;
  final VelaWindowExitGuard? windowExitGuard;
  final VelaWindowsTrayController? windowsTray;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) {
      final palette = settings.palette;
      final brightness = settings.themeMode == ThemeMode.system
          ? WidgetsBinding.instance.platformDispatcher.platformBrightness
          : (settings.themeMode == ThemeMode.light
              ? Brightness.light : Brightness.dark);
      VelaThemeRuntime.select(palette, brightness);
      return MaterialApp(
        title: 'Vela',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: _theme(Brightness.light, palette),
        darkTheme: _theme(Brightness.dark, palette),
        home: _Shell(settings: settings, diagnostics: diagnostics,
          core: core, systemProxy: systemProxy,
          windowExitGuard: windowExitGuard, windowsTray: windowsTray),
      );
    },
  );
}

ThemeData _theme(Brightness brightness, VelaPalette palette) {
  final t = palette.tokens(brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent, brightness: brightness,
    primary: t.accent, secondary: t.accentSoft, surface: t.background);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(color: t.line.withValues(alpha: .6)));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    fontFamily: 'Georgia',
    textTheme: TextTheme(
      headlineSmall: TextStyle(fontFamily: 'Georgia',
        color: t.text, fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontFamily: 'Georgia',
        color: t.text, fontSize: 21, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: t.text, fontSize: 16,
        fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: t.text, fontSize: 15),
      bodyMedium: TextStyle(color: t.text, fontSize: 13.5),
      bodySmall: TextStyle(color: t.muted, fontSize: 12),
    ),
    iconTheme: IconThemeData(color: t.accent, size: 21),
    cardTheme: CardThemeData(elevation: 0,
      color: t.surface.withValues(alpha: .79), shape: shape),
    listTileTheme: ListTileThemeData(
      iconColor: t.accent, textColor: t.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: t.surface.withValues(alpha: .84),
      hintStyle: TextStyle(color: t.muted),
      prefixIconColor: t.accent,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: t.line)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: t.line.withValues(alpha: .8))),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: t.accent, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: t.accent, foregroundColor: Colors.white,
      shape: shape, elevation: 0)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        side: BorderSide(color: t.line),
        shape: shape)),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accent)),
    chipTheme: ChipThemeData(
      backgroundColor: t.surface.withValues(alpha: .8),
      selectedColor: t.accent.withValues(alpha: .24),
      side: BorderSide(color: t.line.withValues(alpha: .55)),
      shape: shape,
      labelStyle: TextStyle(color: t.text)),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      shape: shape),
    dividerTheme: DividerThemeData(
      color: t.line.withValues(alpha: .56), thickness: .75),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.settings, this.diagnostics,
    this.core, this.systemProxy, this.windowExitGuard, this.windowsTray});
  final SettingsController settings;
  final VelaDiagnostics? diagnostics;
  final VelaCoreController? core;
  final VelaSystemProxyManager? systemProxy;
  final VelaWindowExitGuard? windowExitGuard;
  final VelaWindowsTrayController? windowsTray;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  final VelaDemoController demo = VelaDemoController();
  VelaSubscriptionController? subscription;
  VelaRoutingModeController? routing;
  bool _vpnWasConnected = false;
  VelaConnectionCoordinator? connection;
  VelaSmartController? smart;
  VelaAndroidVpnController? androidVpn;
  VelaTrafficMonitor? traffic;
  int tab = 0;
  String? _lastNotifiedAirport;

  // Store only the user's airport display name in Android private prefs.
  // Notification speed is sampled independently by native VpnService.
  void _syncAndroidNotificationName() {
    if (!Platform.isAndroid) return;
    final sub = subscription;
    final name = sub is VelaFlClashSubscriptionController
        ? sub.profileName?.trim() : null;
    final label = name == null || name.isEmpty ? 'Vela' : name;
    if (_lastNotifiedAirport == label) return;
    _lastNotifiedAirport = label;
    unawaited(const MethodChannel('vela_shuo/android_vpn')
        .invokeMethod<void>('setNotificationAirport', {'name': label})
        .catchError((Object _) {}));
  }

  void _synchronizeRouting() {
    final mode = routing;
    final sub = subscription;
    if (mode == null || sub is! VelaFlClashSubscriptionController) return;
    unawaited(mode.synchronize(sub.activeProfileId));
  }

  void _onVpnForRouting() {
    final connected = androidVpn?.connected == true;
    if (connected && !_vpnWasConnected) {
      // The Android VPN service reloads native configuration on startup.
      routing?.invalidateAfterVpnStart();
      _synchronizeRouting();
    }
    _vpnWasConnected = connected;
  }

  void syncRealGlobe() {
    traffic?.sync(Platform.isAndroid
        ? androidVpn?.connected == true : connection?.connected == true);
    final sub = subscription;
    final vpn = androidVpn;
    if (Platform.isAndroid && vpn != null) {
      final state = switch (vpn.phase) {
        VelaAndroidVpnPhase.preparing ||
        VelaAndroidVpnPhase.connecting => VelaPhase.connecting,
        VelaAndroidVpnPhase.connected => VelaPhase.connected,
        VelaAndroidVpnPhase.error => VelaPhase.error,
        VelaAndroidVpnPhase.disconnected => VelaPhase.idle,
      };
      // The VPN service is authoritative, including when returning to
      // the application from the background. No animation-only success.
      demo.projectRealState(state, sub?.selected?.name);
      return;
    }
    final conn = connection;
    if (sub?.selected == null || conn == null) return;
    final phase = switch (conn.phase) {
      VelaRealPhase.connecting => VelaPhase.connecting,
      VelaRealPhase.connected => conn.connected
          ? VelaPhase.connected : VelaPhase.idle,
      _ => VelaPhase.idle,
    };
    demo.projectRealState(phase, sub!.selected!.name);
  }

  @override
  void initState() {
    super.initState();
    traffic = VelaTrafficMonitor(reader: () async {
      if (Platform.isAndroid) {
        return await androidVpn?.readTrafficCounters();
      }
      return await widget.core?.readTrafficCounters();
    });
    if (Platform.isAndroid) {
      androidVpn = VelaAndroidVpnController();
      unawaited(androidVpn!.refresh());
    }
    if (widget.core != null) {
      final runtime = widget.core;
      subscription = runtime is VelaFlClashCoreController
          ? VelaFlClashSubscriptionController(
              backend: runtime.backend, core: runtime)
          : VelaSubscriptionController(
              core: widget.core!, previewOnly: Platform.isAndroid);
      if (runtime is VelaFlClashCoreController) {
        routing = VelaRoutingModeController(runtime.backend);
        unawaited(routing!.restore().then((_) => _synchronizeRouting()));
        subscription!.addListener(_synchronizeRouting);
        subscription!.addListener(_syncAndroidNotificationName);
        _syncAndroidNotificationName();
        runtime.ensureRoutingMode = () async {
          final sub = subscription! as VelaFlClashSubscriptionController;
          if (!await sub.applyPendingProfileIfIdle()) return false;
          await routing!.restore();
          return routing!.synchronize(
              (subscription! as VelaFlClashSubscriptionController).activeProfileId);
        };
      }
      unawaited(subscription!.restoreSaved());
      if (subscription is VelaFlClashSubscriptionController) {
        (subscription! as VelaFlClashSubscriptionController).isVpnActive =
            () => androidVpn?.active == true;
        widget.windowExitGuard?.flushSavedProfiles =
            (subscription! as VelaFlClashSubscriptionController)
                .flushPendingSaves;
      }
      if (Platform.isAndroid) {
        subscription!.addListener(syncRealGlobe);
      }
      if (widget.systemProxy != null && !Platform.isAndroid) {
        connection = VelaConnectionCoordinator(
          core: widget.core!, subscription: subscription!,
          proxy: widget.systemProxy!,
        );
        subscription!.addListener(syncRealGlobe);
        connection!.addListener(syncRealGlobe);
        widget.windowExitGuard?.shutdownConnection = connection!.shutdown;
        widget.windowsTray?.attachConnection(connection!);
      }
      // Android uses the same FlClash Go IPC and measurement algorithms as
      // Windows. Its Android VpnService does not have a WinINet coordinator.
      final nativeProbe = runtime is VelaFlClashCoreController
          ? FlClashGoNodeProbe(runtime.backend) : null;
      if (nativeProbe != null || connection != null) {
        final legacyProbe = nativeProbe == null
            ? VelaIsolatedNodeProbe(
                coreBinary: widget.core!.benchmarkCorePath ?? '')
            : null;
        final VelaNodeLatencyProbe latencyProbe = nativeProbe ?? legacyProbe!;
        final VelaNodeDownloadProbe downloadProbe = nativeProbe ?? legacyProbe!;
        final VelaFullNodeProbe fullProbe = nativeProbe ?? legacyProbe!;
        smart = VelaSmartController(
          subscription: subscription!, core: widget.core!,
          connection: connection,
          sessionActive: Platform.isAndroid
              ? () => androidVpn?.active == true : null,
          sessionBusy: Platform.isAndroid
              ? () => androidVpn?.busy == true : null,
          probe: latencyProbe,
          downloadProbe: downloadProbe, fullProbe: fullProbe,
        );
      }
    }
    if (androidVpn != null) {
      androidVpn!.addListener(syncRealGlobe);
      androidVpn!.addListener(_onVpnForRouting);
      syncRealGlobe();
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.diagnostics?.record(VelaDiagnosticEvent.appResumed);
      if (androidVpn != null) unawaited(androidVpn!.refresh());
    } else if (state == AppLifecycleState.paused) {
      widget.diagnostics?.record(VelaDiagnosticEvent.appPaused);
    } else if (state == AppLifecycleState.detached) {
      if (connection != null) {
        unawaited(connection!.shutdown());
      }
    }
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.removeListener(syncRealGlobe);
    subscription?.removeListener(_synchronizeRouting);
    subscription?.removeListener(_syncAndroidNotificationName);
    connection?.removeListener(syncRealGlobe);
    smart?.dispose();
    androidVpn?.removeListener(syncRealGlobe);
    androidVpn?.removeListener(_onVpnForRouting);
    androidVpn?.dispose();
    traffic?.dispose();
    widget.windowExitGuard?.shutdownConnection = null;
    widget.windowExitGuard?.flushSavedProfiles = null;
    // Restore WinINet BEFORE terminating its local endpoint. Never kill
    // the core synchronously while the system proxy still points at it.
    final link = connection;
    final engine = widget.core;
    if (link != null) {
      unawaited(link.shutdown().whenComplete(() {
        link.dispose();
        engine?.dispose();
      }));
    } else {
      engine?.dispose();
    }
    routing?.dispose();
    subscription?.dispose();
    demo.dispose();
    super.dispose();
  }

  void navigate(int i) => setState(() => tab = i);


  Widget page(bool desktop) => switch (tab) {
    1 => VelaStellarProxyPage(
      demo: demo, subscription: subscription,
      connection: connection, androidVpn: androidVpn,
      smart: smart, traffic: traffic, routing: routing,
      openConfig: () => navigate(4)),
    2 => _SmartPage(demo: demo, smart: smart, subscription: subscription),
    4 => VelaStellarConfigPage(
      demo: demo, subscription: subscription, core: widget.core,
      connection: connection, androidVpn: androidVpn),
    3 => _SettingsPage(
      settings: widget.settings,
      diagnostics: widget.diagnostics, core: widget.core,
      subscription: subscription, connection: connection,
      androidVpn: androidVpn, windowExitGuard: widget.windowExitGuard,
    ),
    _ => _HomePage(
      demo: demo, desktop: desktop,
      connection: connection, subscription: subscription, smart: smart,
      androidVpn: androidVpn, traffic: traffic, routing: routing,
      showNodes: () => navigate(1), showSmart: () => navigate(2),
      onNavigate: navigate,
    ),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 820;
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(fit: StackFit.expand, children: [
          _EarthBackdrop(demo: demo),
          SafeArea(child: Stack(fit: StackFit.expand, children: [
            TweenAnimationBuilder<double>(
              key: ValueKey('vela_page_$tab'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 8), child: child),
              ),
              child: page(desktop),
            ),
            if (tab != 0)
              Positioned(top: desktop ? 14 : 12,
                left: desktop ? 22 : 14,
                child: _VoyageHomeShortcut(
                  onTap: () => navigate(0))),
            Positioned(
              right: desktop ? 27 : null,
              left: desktop ? null : 0,
              bottom: desktop ? 20 : 12,
              child: desktop
                  ? _VoyageDock(selected: tab, onNavigate: navigate)
                  : SizedBox(width: constraints.maxWidth,
                      child: Center(child: _VoyageDock(
                        selected: tab, onNavigate: navigate))),
            ),
          ])),
        ]),

      );
    },
  );
}


class _EarthBackdrop extends StatelessWidget {
  const _EarthBackdrop({required this.demo});
  final VelaDemoController demo;

  @override
  Widget build(BuildContext context) =>
      VelaWorldAtlas(demo: demo);
}

/// Animated master mark shared with launcher and system-tray branding.
class VelaBrandLogo extends StatelessWidget {
  const VelaBrandLogo({super.key, this.size = 65});
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 650),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, (1 - value) * 5),
        child: child,
      ),
    ),
    child: VelaSailMark(size: size),
  );
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.demo,
    required this.desktop,
    required this.showNodes,
    required this.showSmart,
    required this.onNavigate,
    this.connection,
    this.subscription,
    this.smart,
    this.androidVpn,
    this.traffic,
    this.routing,
  });
  final VelaDemoController demo;
  final VelaConnectionCoordinator? connection;
  final VelaSubscriptionController? subscription;
  final VelaSmartController? smart;
  final VelaAndroidVpnController? androidVpn;
  final VelaTrafficMonitor? traffic;
  final VelaRoutingModeController? routing;
  final bool desktop;
  final VoidCallback showNodes;
  final VoidCallback showSmart;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([demo, ?connection,
      ?subscription, ?smart, ?androidVpn, ?traffic]),
    builder: (context, _) => desktop && !Platform.isAndroid
      ? _DesktopHome(
          demo: demo, connection: connection, subscription: subscription,
          smart: smart, traffic: traffic, routing: routing,
          showNodes: showNodes, showSmart: showSmart,
          onNavigate: onNavigate,
        )
      : _MobileHome(
          demo: demo, connection: connection, subscription: subscription,
          smart: smart, androidVpn: androidVpn, traffic: traffic,
          routing: routing, showNodes: showNodes,
        ),
  );
}

class _DesktopHome extends StatelessWidget {
  const _DesktopHome({
    required this.demo, required this.showNodes, required this.showSmart,
    required this.onNavigate,
    this.connection, this.subscription, this.smart, this.traffic, this.routing,
  });
  final VelaDemoController demo;
  final VelaConnectionCoordinator? connection;
  final VelaSubscriptionController? subscription;
  final VelaSmartController? smart;
  final VelaTrafficMonitor? traffic;
  final VelaRoutingModeController? routing;
  final VoidCallback showNodes;
  final VoidCallback showSmart;
  final ValueChanged<int> onNavigate;

  void _toggle(BuildContext context) {
    final conn = connection;
    if (conn != null) {
      unawaited(_toggleRealConnection(context, conn));
    } else if (demo.isConnected || demo.phase == VelaPhase.connecting ||
        demo.phase == VelaPhase.switching) {
      demo.disconnect();
    } else {
      demo.connect();
    }
  }

  void _openRouting(BuildContext context) {
    final modes = routing;
    if (modes == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: VelaRoutingModeSelector(
            key: const ValueKey('home_routing_selector'),
            controller: modes,
            activeProfileId:
                subscription is VelaFlClashSubscriptionController
                    ? (subscription! as VelaFlClashSubscriptionController)
                        .activeProfileId
                    : null,
            locked: connection?.busy == true || smart?.scanning == true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 1000;
      final connected = connection?.connected ?? demo.isConnected;
      final busy = connection?.busy == true ||
          (connection == null && (demo.phase == VelaPhase.connecting ||
          demo.phase == VelaPhase.switching));
      final node = connection?.nodeName ??
          ('UI 演示 · ' + demo.selected.title);
      final state = busy ? '正在建立航线' :
          connected ? '已连接' : '未连接';
      return Stack(children: [
        Positioned(
          left: narrow ? 20 : 32, top: narrow ? 16 : 25,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const VelaSailMark(size: 37),
            const SizedBox(width: 9),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
              Text('VELA', style: TextStyle(color: _foreground,
                fontWeight: FontWeight.w800, fontSize: narrow ? 25 : 30,
                letterSpacing: 2.8)),
              Text(velaBrandTagline, style: TextStyle(
                color: _muted, fontSize: 9, letterSpacing: .9)),
            ]),
          ]),
        ),
        Positioned(
          right: narrow ? 16 : 29, top: narrow ? 15 : 22,
          width: narrow ? 302 : 356,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                key: const ValueKey('immersive_connection'),
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(
                  color: _panel.withValues(alpha: .69),
                  border: Border.all(color: _line.withValues(alpha: .65)),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(children: [
                  Icon(Icons.circle, size: 9,
                    color: busy ? _blue : connected ? _mint : _muted),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(state, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _foreground,
                          fontSize: 13, fontWeight: FontWeight.w700)),
                      if (connected) Text(
                        VelaSessionTime.format(connection?.connectedDuration),
                        key: const ValueKey('desktop_connection_uptime'),
                        style: TextStyle(color: _blue, fontSize: 10)),
                      Text(node, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 10)),
                    ],
                  )),
                  if (routing != null)
                    IconButton(
                      key: const ValueKey('home_routing_open'),
                      tooltip: '航线模式：' + routing!.current.label,
                      icon: const Icon(Icons.alt_route_rounded),
                      iconSize: 21, color: _blue,
                      onPressed: () => _openRouting(context),
                    ),
                  const SizedBox(width: 5),
                  IconButton.filled(
                    key: const ValueKey('immersive_power_button'),
                    tooltip: busy ? '正在连接' :
                        connected ? '安全断开' : '连接',
                    onPressed: busy ? null : () => _toggle(context),
                    icon: Icon(connected
                        ? Icons.power_settings_new_rounded
                        : Icons.sailing_rounded, size: 24),
                    style: IconButton.styleFrom(
                      backgroundColor: _blue.withValues(alpha: .87),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          left: narrow ? 16 : 29, bottom: narrow ? 14 : 27,
          child: _VoyageRatePanel(traffic: traffic,
            active: connection?.connected ?? false),
        ),
      ]);
    },
  );
}

class _VoyageRatePanel extends StatelessWidget {
  const _VoyageRatePanel({required this.traffic, required this.active});
  final VelaTrafficMonitor? traffic;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final upload = VelaVoyageSpeed.format(
        active ? traffic?.uploadBytesPerSecond : null);
    final download = VelaVoyageSpeed.format(
        active ? traffic?.downloadBytesPerSecond : null);
    return ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          key: const ValueKey('voyage_speed_panel'),
          width: 283, height: 79,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: _panel.withValues(
              alpha: defaultTargetPlatform == TargetPlatform.android
                  ? .50 : .72),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: _line.withValues(alpha: .65)),
          ),
          child: Row(children: [
            Expanded(child: _VoyageRate(label: '风速 · 上传',
              icon: Icons.north_east_rounded,
              number: upload.$1, unit: upload.$2)),
            Container(width: 1, height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 11),
              color: _line.withValues(alpha: .60)),
            Expanded(child: _VoyageRate(label: '航速 · 下载',
              icon: Icons.south_west_rounded,
              number: download.$1, unit: download.$2)),
          ]),
        ),
      ),
    );
  }
}

class _VoyageRate extends StatelessWidget {
  const _VoyageRate({required this.label, required this.icon,
      required this.number, required this.unit});
  final String label;
  final IconData icon;
  final String number;
  final String unit;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(icon, color: _blue, size: 14),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _muted, fontSize: 11))),
      ]),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: number, style: TextStyle(
            color: _foreground, fontSize: 20,
            fontWeight: FontWeight.w700)),
          TextSpan(text: unit.isEmpty ? '' : ' $unit',
            style: TextStyle(color: _muted, fontSize: 10)),
        ]))),
    ],
  );
}

/// Four truly separate floating travel-journal buttons. No shared pill.
class _VoyageDock extends StatelessWidget {
  const _VoyageDock({required this.onNavigate, required this.selected});
  final ValueChanged<int> onNavigate;
  final int selected;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min, children: [
      for (final (target, symbol, hint) in const [
        (1, VelaVoyageSymbol.globe, '代理节点'),
        (4, VelaVoyageSymbol.logbook, '机场配置'),
        (2, VelaVoyageSymbol.compass, '智能优选'),
        (3, VelaVoyageSymbol.helm, '系统设置'),
      ])
        Padding(padding: const EdgeInsets.only(left: 11),
          child: Tooltip(message: hint,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: VelaWatercolorSurface(
                  selected: selected == target,
                  padding: EdgeInsets.zero,
                  radius: 17,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('nav_$target'),
                      onTap: () => onNavigate(target),
                      borderRadius: BorderRadius.circular(17),
                      child: SizedBox(width: 49, height: 49,
                        child: Center(child: VelaVoyageGlyph(
                          symbol: symbol, size: 26,
                          active: selected == target))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _VoyageHomeShortcut extends StatelessWidget {
  const _VoyageHomeShortcut({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
      child: VelaWatercolorSurface(
        radius: 18, padding: EdgeInsets.zero,
        child: Material(color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('nav_0'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const VelaSailMark(size: 27),
                const SizedBox(width: 7),
                Text('VELA  /  HOME', style: TextStyle(
                  fontFamily: 'Georgia', letterSpacing: 1.3,
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: _foreground)),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DemoTag extends StatelessWidget {
  const _DemoTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: _panel.withValues(alpha:
          VelaThemeRuntime.active.dark ? .50 : .50),
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.visibility_outlined, color: _blue, size: 14),
      SizedBox(width: 6),
      Text('UI 演示 · 尚未接入代理',
          style: TextStyle(color: _muted, fontSize: 11)),
    ]),
  );
}

/// Local, legible frosted surface; the Earth outside this card is untouched.
/// Hover elevation is subtle to preserve a calm, precise interface.
class _GlassCard extends StatefulWidget {
  const _GlassCard({
    required this.child,
  });
  final Widget child;
  @override
  State<_GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<_GlassCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: VelaWatercolorSurface(
          hovered: _hover, padding: const EdgeInsets.all(18),
          child: widget.child),
      ),
    ),
  );
}

/// Android shares the Windows map-first visual hierarchy. Native VpnService
/// remains authoritative for connection state and its OS authorization.
class _MobileHome extends StatelessWidget {
  const _MobileHome({
    required this.demo, required this.showNodes,
    this.connection, this.subscription, this.androidVpn,
    this.traffic, this.routing, this.smart,
  });
  final VelaDemoController demo;
  final VelaConnectionCoordinator? connection;
  final VelaSubscriptionController? subscription;
  final VelaAndroidVpnController? androidVpn;
  final VelaTrafficMonitor? traffic;
  final VelaRoutingModeController? routing;
  final VelaSmartController? smart;
  final VoidCallback showNodes;

  Future<void> _toggle(BuildContext context) async {
    final vpn = androidVpn;
    if (vpn != null) {
      if (vpn.busy) return;
      if (vpn.active) {
        await vpn.stop();
        return;
      }
      final sub = subscription;
      if (sub == null || sub.androidVpnProfile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先导入有效机场配置，再连接 VPN')));
        return;
      }
      // The first-use Android VPN permission dialog is REQUIRED by Android.
      if (sub is VelaFlClashSubscriptionController &&
          !await sub.applyPendingProfileIfIdle()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('新机场配置加载失败，VPN 未启动')));
        }
        return;
      }
      // Unlike FlClash's full app, this host does not own a persistent
      // native setting object. Synchronize before passing route-mode to
      // VpnService; quickSetup must then reapply it before establishing TUN.
      final routingController = routing;
      if (sub is VelaFlClashSubscriptionController &&
          routingController != null &&
          !await routingController.synchronize(sub.activeProfileId)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('规则模式尚未被 FlClash 核心确认，VPN 未启动')));
        }
        return;
      }
      await vpn.start(sub);
      if (vpn.error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(vpn.error!)));
      }
      return;
    }
    final conn = connection;
    if (conn != null) {
      await _toggleRealConnection(context, conn);
    } else if (demo.isConnected || demo.phase == VelaPhase.connecting ||
        demo.phase == VelaPhase.switching) {
      demo.disconnect();
    } else {
      demo.connect();
    }
  }

  void _openRouting(BuildContext context) {
    final modes = routing;
    if (modes == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: VelaRoutingModeSelector(
            key: const ValueKey('mobile_routing_selector'),
            controller: modes,
            activeProfileId:
                subscription is VelaFlClashSubscriptionController
                    ? (subscription! as VelaFlClashSubscriptionController)
                        .activeProfileId : null,
            locked: androidVpn?.busy == true ||
                connection?.busy == true || smart?.scanning == true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final vpn = androidVpn;
      final connected = vpn?.connected ??
          connection?.connected ?? demo.isConnected;
      final busy = vpn?.busy ?? connection?.busy ??
          (demo.phase == VelaPhase.connecting ||
           demo.phase == VelaPhase.switching);
      final node = subscription?.selected?.name ??
          (vpn != null ? '尚未选择航线' : 'UI 演示 · ' + demo.selected.title);
      final state = vpn?.phaseText ??
          (busy ? '正在建立航线' : connected ? '已连接' : '未连接');
      return Stack(children: [
        Positioned(
          top: 13, left: 16, right: 12,
          child: Row(children: [
            const VelaSailMark(size: 40),
            const SizedBox(width: 9),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VELA', style: TextStyle(color: _foreground,
                    fontSize: 26, fontWeight: FontWeight.w800,
                    letterSpacing: 2.5)),
                Text(velaBrandTagline, style: TextStyle(
                    color: _muted, fontSize: 9)),
              ],
            )),
            if (vpn != null)
              Icon(Icons.shield_outlined, size: 18,
                  color: connected ? _mint : _blue),
          ]),
        ),
        Positioned(
          top: 90, left: 14, right: 14,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: VelaWatercolorSurface(
                radius: 24,
                padding: const EdgeInsets.fromLTRB(14, 8, 9, 8),
                child: Row(children: [
                  Icon(Icons.circle, size: 9, color:
                      busy ? _blue : connected ? _mint : _muted),
                  const SizedBox(width: 9),
                  Expanded(child: InkWell(
                    key: const ValueKey('mobile_node_shortcut'),
                    onTap: showNodes,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(state, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _foreground,
                            fontSize: 14, fontWeight: FontWeight.w700)),
                        if (connected) Text(
                          VelaSessionTime.format(vpn?.connectedDuration ??
                              connection?.connectedDuration),
                          key: const ValueKey('mobile_connection_uptime'),
                          style: TextStyle(color: _blue, fontSize: 11)),
                        Text(node, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted, fontSize: 11)),
                      ],
                    ),
                  )),
                  if (routing != null)
                    IconButton(
                      key: const ValueKey('mobile_routing_open'),
                      tooltip: '航线模式：' + routing!.current.label,
                      icon: const Icon(Icons.alt_route_rounded),
                      iconSize: 21, color: _blue,
                      onPressed: () => _openRouting(context)),
                  IconButton.filled(
                    key: ValueKey(vpn != null
                        ? 'android_vpn_button' : 'mobile_connect_button'),
                    tooltip: busy ? '正在连接' :
                        connected ? '断开航线' : '启航连接',
                    onPressed: busy ? null : () => _toggle(context),
                    icon: Icon(connected
                        ? Icons.power_settings_new_rounded
                        : Icons.sailing_rounded, size: 24),
                    style: IconButton.styleFrom(
                      backgroundColor: _blue.withValues(alpha: .9),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (vpn?.error != null)
          Positioned(top: 178, left: 18, right: 18,
            child: VelaWatercolorSurface(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Text(vpn!.error!, maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11,
                      color: Color(0xFFE78986))))),
        Positioned(
          left: 14, bottom: 90,
          child: _VoyageRatePanel(
            traffic: traffic, active: vpn?.connected ??
                connection?.connected ?? false),
        ),
      ]);
    },
  );
}

class _ScreenHeading extends StatelessWidget {
  const _ScreenHeading(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(
        color: _foreground, fontSize: 29, fontWeight: FontWeight.bold,
      )),
      SizedBox(height: 7),
      Text(subtitle, style: TextStyle(color: _muted)),
    ],
  );
}

class _ScreenPadding extends StatelessWidget {
  const _ScreenPadding({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: Platform.isAndroid ? 1000 : 870),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 75, 16, 115),
        child: child,
      ),
    ),
  );
}

class _SmartPage extends StatelessWidget {
  const _SmartPage({required this.demo, this.smart, this.subscription});
  final VelaDemoController demo;
  final VelaSmartController? smart;
  final VelaSubscriptionController? subscription;

  @override
  Widget build(BuildContext context) {
    if (smart != null && subscription?.nodes.isNotEmpty == true) {
      return _ScreenPadding(child: ListView(children: [
        _ScreenHeading('智能优选', Platform.isAndroid
            ? '原生航线测速 · VPN 连接保护'
            : '真实 HTTPS 测速 · 稳定优先'),
        SizedBox(height: 18),
        _RealTag(),
        SizedBox(height: 22),
        VelaSmartPanel(engine: smart!, subscription: subscription!),
      ]));
    }
    return AnimatedBuilder(
    animation: demo,
    builder: (context, _) => _ScreenPadding(child: ListView(children: [
      _ScreenHeading('智能优选', '稳定优先 · 让每一次连接更从容'),
      SizedBox(height: 18),
      _DemoTag(),
      SizedBox(height: 13),
      _GlassCard(child: Column(children: [
        SwitchListTile(
          secondary: Icon(Icons.auto_awesome, color: _blue),
          title: Text('智能优选（界面演示）'),
          subtitle: Text('暂不执行测速或自动切换'),
          value: demo.smartEnabled,
          onChanged: demo.setSmart,
        ),
        Divider(color: _line, height: 1),
        SwitchListTile(
          secondary: Icon(Icons.shield_outlined, color: _blue),
          title: Text('活跃连接保护（界面演示）'),
          subtitle: Text('真实保护功能将在内核接入后实现'),
          value: demo.protectConnections,
          onChanged: demo.setProtection,
        ),
      ])),
      SizedBox(height: 17),
      _GlassCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SHUO Smart Engine',
              style: TextStyle(
                color: _foreground, fontSize: 19,
                fontWeight: FontWeight.bold,
              )),
          SizedBox(height: 12),
          Text(
            '规划支持真实下载测速、历史评分、分批轮测、切换冷却和故障恢复。'
            '当前仅用于确认页面布局，不包含真实智能优选算法。',
            style: TextStyle(color: _muted, height: 1.7),
          ),
        ],
      )),
    ])),
  );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.settings, this.diagnostics, this.core,
    this.subscription, this.connection, this.androidVpn,
    this.windowExitGuard,
  });
  final SettingsController settings;
  final VelaDiagnostics? diagnostics;
  final VelaCoreController? core;
  final VelaSubscriptionController? subscription;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;
  final VelaWindowExitGuard? windowExitGuard;
  @override
  Widget build(BuildContext context) => _ScreenPadding(
    child: ListView(children: [
      _ScreenHeading('设置', '为 Vela 定义你的使用方式'),
      SizedBox(height: 18),
      Platform.isAndroid ? _AndroidVpnTag(vpn: androidVpn!) :
          subscription?.selected != null ? _RealTag() :
              (core == null ? _DemoTag() :
                  const Text('请先添加机场配置')),
      SizedBox(height: 24),
      if (core != null) ...[
        if (!Platform.isAndroid) ...[
          VelaCoreSettingsCard(controller: core!,
            connection: connection),
          SizedBox(height: 16),
        ],
      ],
      _PalettePicker(settings: settings),
      SizedBox(height: 16),
      _GlassCard(child: Column(children: [
        ListTile(
          leading: Icon(Icons.palette_outlined, color: _blue),
          title: Text('外观主题'),
          subtitle: Text('设置自动保存'),
          trailing: DropdownButton<ThemeMode>(
            value: settings.themeMode,
            dropdownColor: _panel,
            items: const [
              DropdownMenuItem(value: ThemeMode.dark,
                  child: Text('深色')),
              DropdownMenuItem(value: ThemeMode.light,
                  child: Text('浅色')),
              DropdownMenuItem(value: ThemeMode.system,
                  child: Text('跟随系统')),
            ],
            onChanged: (mode) {
              if (mode != null) settings.setThemeMode(mode);
            },
          ),
        ),
        Divider(height: 1, color: _line),
        ListTile(
          key: const ValueKey('vela_about'),
          leading: Icon(Icons.info_outline, color: _blue),
          title: const Text('关于 Vela'),
          subtitle: Text('Vela v${VelaUpdateService.currentVersion} · '
              '${Platform.isAndroid ? "Android" : "Windows"}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Vela',
            applicationVersion: VelaUpdateService.currentVersion,
            applicationLegalese: '© Vela',
            children: [
              Text(Platform.isAndroid
                  ? 'FlClash / Mihomo 原生 VPN；支持正式签名覆盖升级。'
                  : 'FlClash / Mihomo 系统代理；更新前请安全退出。'),
            ],
          ),
        ),
        Divider(height: 1, color: _line),
        ListTile(
          key: const ValueKey('vela_check_update'),
          leading: Icon(Icons.system_update_alt_rounded, color: _blue),
          title: const Text('检查更新'),
          subtitle: const Text('通过 Vela 官方 GitHub Release 获取已验证安装包'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            try {
              final info = await const VelaUpdateService().check();
              if (!context.mounted) return;
              if (!info.available || info.assetUrl == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前已是最新正式版本')));
                return;
              }
              final accepted = await showDialog<bool>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: Text('发现 Vela ${info.latestVersion}'),
                  content: Text(Platform.isAndroid
                      ? '将打开官方 APK 下载页面。使用相同签名的正式版支持覆盖更新。'
                      : '将下载 Windows 便携压缩包。请先安全退出，再替换旧版文件。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('稍后')),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('下载更新')),
                  ],
                ),
              );
              if (accepted == true) {
                final opened = await launchUrl(info.assetUrl!,
                    mode: LaunchMode.externalApplication);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('无法打开下载链接')));
                }
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('检查更新失败，请确认网络后重试')));
              }
            }
          },
        ),
        if (Platform.isWindows && windowExitGuard != null) ...[
          Divider(height: 1, color: _line),
          ListTile(
            key: const ValueKey('windows_exit_action'),
            leading: Icon(Icons.power_settings_new_rounded, color: _blue),
            title: const Text('退出程序'),
            subtitle: const Text('点击 × 隐藏到系统托盘；点击 — 最小化到任务栏。'
                '托盘右键可开启/关闭代理与安全退出。'),
            trailing: OutlinedButton(
              onPressed: () async {
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('退出 Vela？'),
                    content: const Text('将断开当前连接、恢复 Windows 系统代理设置，'
                        '然后安全关闭程序。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialog).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialog).pop(true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (accepted != true || !context.mounted) return;
                final restored = await windowExitGuard!.closeSafely();
                if (!restored && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content:
                        Text('未能安全恢复系统代理，程序仍在运行，请检查后重试。')),
                  );
                }
              },
              child: const Text('安全退出'),
            ),
          ),
        ],
      ])),
      SizedBox(height: 16),
      if (diagnostics != null) ...[
        SizedBox(height: 16),
        _DiagnosticsCard(diagnostics: diagnostics!),
      ],
      SizedBox(height: 16),
      _GlassCard(child: ListTile(
        leading: Icon(Icons.privacy_tip_outlined, color: _blue),
        title: Text('隐私与安全'),
        subtitle: Text(Platform.isAndroid
            ? 'VPN 授权由 Android 系统管理；不上传遥测数据。'
            : '无需 VPN 权限，不上传遥测数据。',
            style: TextStyle(color: _muted)),
      )),
    ]),
  );
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.diagnostics});
  final VelaDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: diagnostics,
    builder: (context, _) => _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本地诊断（隐私保护）', style: TextStyle(
            color: _foreground, fontSize: 17, fontWeight: FontWeight.w600,
          )),
          SizedBox(height: 8),
          Text(
            '仅记录时间与预定义事件代码，不记录订阅、地址、密钥、'
            '异常原文或流量内容；不上传网络。',
            style: TextStyle(color: _muted, height: 1.5, fontSize: 12),
          ),
          SizedBox(height: 10),
          Text(
            '当前会话 ${diagnostics.recentEntries.length} 条 · '
            '${diagnostics.persistent ? '本机日志已启用' : '仅内存记录'}',
            style: TextStyle(color: _blue, fontSize: 12),
          ),
          SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: diagnostics.report));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('已复制脱敏诊断记录'),
                ));
              },
              icon: Icon(Icons.copy_rounded, size: 17),
              label: Text('复制诊断记录'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final result = await diagnostics.clear();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(result ? '本地诊断记录已清除' : '清除失败，请稍后重试'),
                ));
              },
              icon: Icon(Icons.delete_outline_rounded, size: 17),
              label: Text('清除诊断记录'),
            ),
          ]),
        ],
      ),
    ),
  );
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => _GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.palette_outlined, color: _blue, size: 22),
          SizedBox(width: 10),
          Text('主题配色', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600,
            color: _foreground,
          )),
          Spacer(),
          Text('8 套', style: TextStyle(color: _muted, fontSize: 12)),
        ]),
        SizedBox(height: 7),
        Text('Color Hunt · Popular / All time 前 8 套配色',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 680 ? 4 : 2;
          final spacing = 12.0;
          final width = (constraints.maxWidth - spacing * (columns - 1))
              / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: 12,
            children: [
              for (final palette in VelaPalette.all)
                SizedBox(
                  width: width,
                  child: _PaletteOption(
                    palette: palette,
                    selected: settings.paletteId == palette.id,
                    onTap: () => settings.setPalette(palette.id),
                  ),
                ),
            ],
          );
        }),
      ],
    ),
  );
}

class _PaletteOption extends StatelessWidget {
  const _PaletteOption({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final VelaPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? _blue.withValues(alpha: .14) : _panel.withValues(alpha: .50),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? _blue : _line,
        width: selected ? 2 : 1,
      ),
    ),
    child: InkWell(
      key: ValueKey('palette_${palette.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(7),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(children: [
              Column(children: [
                for (final swatch in palette.swatches)
                  Container(height: 20, color: swatch),
              ]),
              if (selected)
                Positioned(
                  top: 5, right: 6,
                  child: Icon(Icons.check_circle, color: _foreground, size: 18,
                    shadows: [Shadow(color: Colors.black, blurRadius: 6)]),
                ),
            ]),
          ),
          SizedBox(height: 8),
          Text(palette.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12, fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _blue : _foreground,
            )),
        ]),
      ),
    ),
  );
}

class _AndroidVpnTag extends StatelessWidget {
  const _AndroidVpnTag({required this.vpn});
  final VelaAndroidVpnController vpn;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: _blue.withValues(alpha: .13),
      border: Border.all(color: _blue.withValues(alpha: .35)),
    ),
    child: Text(vpn.connected ? 'Vela VPN · 已连接'
        : 'Vela VPN · Beta',
        style: const TextStyle(fontSize: 10)),
  );
}


class _RealTag extends StatelessWidget {
  const _RealTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: 13, vertical: 8,
    ),
    decoration: BoxDecoration(
      color: _mint.withValues(alpha: .11),
      border: Border.all(color: _mint.withValues(alpha: .36)),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text('真实代理模式 · Windows 系统代理',
      style: TextStyle(color: _foreground, fontSize: 11),
    ),
  );
}

Future<void> _toggleRealConnection(
    BuildContext context, VelaConnectionCoordinator connection) async {
    if (connection.busy) return;
    if (connection.connected || connection.proxy.active) {
      await connection.disconnect();
      return;
    }
    if (!connection.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「配置」中导入订阅，并在「代理」中选择节点')),
      );
      return;
    }
    // The user explicitly chose one-click behavior. Retain the coordinator's
    // HTTPS verification, proxy snapshot, rollback and safe disconnect.
    final ok = await connection.connect();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(connection.error ?? '连接失败，系统代理未更改')));
    }
  }


