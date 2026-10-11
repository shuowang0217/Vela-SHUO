// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vela_shuo/src/diagnostics/vela_diagnostics.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/core/vela_system_proxy.dart';
import 'package:vela_shuo/src/core/vela_window_exit_guard.dart';
import 'package:vela_shuo/src/core/vela_connection_coordinator.dart';
import 'package:vela_shuo/src/android/vela_android_vpn.dart';
import 'package:vela_shuo/src/traffic/vela_traffic_monitor.dart';
import 'package:vela_shuo/src/smart/vela_node_probe.dart';
import 'package:vela_shuo/src/smart/vela_smart_controller.dart';
import 'package:vela_shuo/src/smart/vela_smart_panel.dart';
import 'package:vela_shuo/src/core/vela_core_settings_card.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_card.dart';
import 'package:vela_shuo/src/subscription/vela_node_filter_panel.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_controller.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/globe.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';
import 'package:vela_shuo/src/theme/vela_palettes.dart';

Color get _background => VelaThemeRuntime.active.background;
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
  });
  final SettingsController settings;
  final VelaDiagnostics? diagnostics;
  final VelaCoreController? core;
  final VelaSystemProxyManager? systemProxy;
  final VelaWindowExitGuard? windowExitGuard;

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
        title: 'Vela-SHUO',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: _theme(Brightness.light, palette),
        darkTheme: _theme(Brightness.dark, palette),
        home: _Shell(settings: settings, diagnostics: diagnostics,
          core: core, systemProxy: systemProxy,
          windowExitGuard: windowExitGuard),
      );
    },
  );
}

ThemeData _theme(Brightness brightness, VelaPalette palette) {
  final tokens = palette.tokens(brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: tokens.accent,
    brightness: brightness,
    surface: tokens.background,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.settings, this.diagnostics,
    this.core, this.systemProxy, this.windowExitGuard});
  final SettingsController settings;
  final VelaDiagnostics? diagnostics;
  final VelaCoreController? core;
  final VelaSystemProxyManager? systemProxy;
  final VelaWindowExitGuard? windowExitGuard;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  final VelaDemoController demo = VelaDemoController();
  VelaSubscriptionController? subscription;
  VelaConnectionCoordinator? connection;
  VelaSmartController? smart;
  VelaAndroidVpnController? androidVpn;
  VelaTrafficMonitor? traffic;
  int tab = 0;

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
      subscription = VelaSubscriptionController(
          core: widget.core!, previewOnly: Platform.isAndroid);
      unawaited(subscription!.restoreSaved());
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
        final benchmark = VelaIsolatedNodeProbe(
          coreBinary: widget.core!.benchmarkCorePath ?? '',
        );
        smart = VelaSmartController(
          subscription: subscription!, core: widget.core!,
          connection: connection!, probe: benchmark,
          downloadProbe: benchmark, fullProbe: benchmark,
        );
      }
    }
    if (androidVpn != null) {
      androidVpn!.addListener(syncRealGlobe);
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

  static const destinations = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, '首页'),
    (Icons.language_outlined, Icons.language_rounded, '节点'),
    (Icons.auto_graph_outlined, Icons.auto_graph_rounded, '智能优选'),
    (Icons.settings_outlined, Icons.settings_rounded, '设置'),
  ];

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.removeListener(syncRealGlobe);
    connection?.removeListener(syncRealGlobe);
    smart?.dispose();
    androidVpn?.removeListener(syncRealGlobe);
    androidVpn?.dispose();
    traffic?.dispose();
    widget.windowExitGuard?.shutdownConnection = null;
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
    subscription?.dispose();
    demo.dispose();
    super.dispose();
  }

  void navigate(int i) => setState(() => tab = i);

  Widget page(bool desktop) => switch (tab) {
    1 => _NodesPage(demo: demo, subscription: subscription,
      core: widget.core, connection: connection, androidVpn: androidVpn,
      smart: smart, goHome: () => navigate(0)),
    2 => _SmartPage(demo: demo, smart: smart, subscription: subscription),
    3 => _SettingsPage(
      demo: demo, settings: widget.settings,
      diagnostics: widget.diagnostics, core: widget.core,
      subscription: subscription, connection: connection,
      androidVpn: androidVpn, goHome: () => navigate(0),
    ),
    _ => _HomePage(
      demo: demo, desktop: desktop,
      connection: connection, subscription: subscription, smart: smart,
      androidVpn: androidVpn, traffic: traffic,
      showNodes: () => navigate(1), showSmart: () => navigate(2),
    ),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 820;
      final extended = constraints.maxWidth >= 1250;
      return Scaffold(
        backgroundColor: _background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [_background, VelaThemeRuntime.active.raised, _background],
            ),
          ),
          child: SafeArea(
            child: Row(children: [
              if (desktop)
                Container(
                  width: extended ? 190 : 90,
                  decoration: BoxDecoration(
                    color: _panel.withValues(alpha: .84),
                    border: Border(right: BorderSide(color: _line)),
                  ),
                  child: _DesktopNav(
                    selected: tab, extended: extended, onSelect: navigate,
                  ),
                ),
              Expanded(child: page(desktop)),
            ]),
          ),
        ),
        bottomNavigationBar: desktop ? null : Container(
          decoration: BoxDecoration(
            color: _panel,
            border: Border(top: BorderSide(color: _line)),
          ),
          child: NavigationBar(
            height: 68,
            backgroundColor: Colors.transparent,
            indicatorColor: _blue.withValues(alpha: .15),
            selectedIndex: tab,
            onDestinationSelected: navigate,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final (outline, filled, label) in destinations)
                NavigationDestination(
                  icon: Icon(outline, color: _muted),
                  selectedIcon: Icon(filled, color: _blue),
                  label: label,
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _DesktopNav extends StatelessWidget {
  const _DesktopNav({
    required this.selected,
    required this.extended,
    required this.onSelect,
  });
  final int selected;
  final bool extended;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Column(children: [
    SizedBox(height: 32),
    VelaBrandLogo(size: 68),
    if (extended) ...[
      SizedBox(height: 8),
      Text('VELA', style: TextStyle(
        color: _foreground, fontSize: 21,
        letterSpacing: 3, fontWeight: FontWeight.w700,
      )),
      Text('— SHUO —', style: TextStyle(
        color: _blue, fontSize: 12, letterSpacing: 2,
      )),
     ],
    SizedBox(height: 46),
    for (var i = 0; i < _ShellState.destinations.length; i++)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Material(
          color: selected == i
              ? _blue.withValues(alpha: .15) : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            key: ValueKey('nav_$i'),
            onTap: () => onSelect(i),
            borderRadius: BorderRadius.circular(13),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: selected == i
                    ? _blue.withValues(alpha: .38) : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  if (extended) SizedBox(width: 15),
                  Icon(
                    selected == i
                        ? _ShellState.destinations[i].$2
                        : _ShellState.destinations[i].$1,
                    color: selected == i ? _blue : _muted, size: 22,
                  ),
                  if (extended) ...[
                    SizedBox(width: 15),
                    Text(_ShellState.destinations[i].$3,
                      style: TextStyle(
                        color: selected == i ? _foreground : _muted,
                        fontWeight: selected == i
                            ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    Spacer(),
  ]);
}

class VelaBrandLogo extends StatelessWidget {
  const VelaBrandLogo({super.key, this.size = 65});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * .75),
    painter: _SailLogoPainter(),
  );
}

class _SailLogoPainter extends CustomPainter {
  const _SailLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final left = Path()
      ..moveTo(w * .52, h * .02)
      ..lineTo(w * .14, h * .77)
      ..lineTo(w * .52, h * .77)..close();
    final right = Path()
      ..moveTo(w * .59, h * .21)
      ..lineTo(w * .91, h * .77)
      ..lineTo(w * .59, h * .77)..close();
    canvas.drawPath(left, Paint()
      ..shader = LinearGradient(
        colors: [Color(0xFFB7E7FF), Color(0xFF448DBF)],
      ).createShader(Offset.zero & size));
    canvas.drawPath(right, Paint()..color = Color(0xFF8DBCD8));
    final hull = Path()
      ..moveTo(w * .1, h * .88)
      ..quadraticBezierTo(w * .52, h * 1.03, w * .94, h * .88);
    canvas.drawPath(hull, Paint()
      ..color = Color(0xFFB7E7FF)
      ..strokeWidth = w * .026
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_SailLogoPainter oldDelegate) => false;
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.demo,
    required this.desktop,
    required this.showNodes,
    required this.showSmart,
    this.connection,
    this.subscription,
    this.smart,
    this.androidVpn,
    this.traffic,
  });
  final VelaDemoController demo;
  final VelaConnectionCoordinator? connection;
  final VelaSubscriptionController? subscription;
  final VelaSmartController? smart;
  final VelaAndroidVpnController? androidVpn;
  final VelaTrafficMonitor? traffic;
  final bool desktop;
  final VoidCallback showNodes;
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([demo, ?connection,
      ?subscription, ?smart, ?androidVpn, ?traffic]),
    builder: (context, _) => desktop && !Platform.isAndroid
      ? _DesktopHome(
          demo: demo, connection: connection, subscription: subscription,
          smart: smart, traffic: traffic,
          showNodes: showNodes, showSmart: showSmart,
        )
      : _MobileHome(
          demo: demo, connection: connection, subscription: subscription,
          smart: smart, androidVpn: androidVpn, traffic: traffic,
          showNodes: showNodes, showSmart: showSmart,
        ),
  );
}

class _DesktopHome extends StatelessWidget {
  const _DesktopHome({
    required this.demo, required this.showNodes, required this.showSmart,
    this.connection, this.subscription, this.smart, this.traffic,
  });
  final VelaDemoController demo;
  final VelaConnectionCoordinator? connection;
  final VelaSubscriptionController? subscription;
  final VelaSmartController? smart;
  final VelaTrafficMonitor? traffic;
  final VoidCallback showNodes;
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Fit the entire desktop dashboard to the available client area.
      // Unlike a forced 790px scroll canvas, the default Windows window
      // can display the connection controls and four metric cards together.
      final availableWidth = constraints.maxWidth;
      final availableHeight = constraints.maxHeight;
      final designWidth = math.max(820.0, math.min(availableWidth - 24, 1320.0));
      const designHeight = 760.0;
      final globeSize = math.min(designWidth * .94, 960.0);

      return Center(
        child: SizedBox(
          width: availableWidth,
          height: availableHeight,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(
              width: designWidth,
              height: designHeight,
              child: Stack(clipBehavior: Clip.hardEdge, children: [
                Positioned(
                  top: -globeSize * .16,
                  right: -globeSize * .10,
                  width: globeSize,
                  height: globeSize,
                  child: IgnorePointer(child: VelaGlobe(demo: demo)),
                ),
                Positioned(top: 20, right: 12, child: subscription?.selected
                    != null ? _RealTag() : _DemoTag()),
                Positioned(left: 22, top: 62, child: _HeroIdentity()),
                Positioned(
                  left: 18,
                  top: 318,
                  width: math.min(designWidth * .47, 520.0),
                  child: subscription?.selected != null && connection != null
                      ? _RealConnectionCard(
                          connection: connection!, showNodes: showNodes)
                      : _ConnectionCard(demo: demo, showNodes: showNodes),
                ),
                Positioned(
                  left: 12, right: 12, bottom: 18,
                  child: _Stats(demo: demo, showSmart: showSmart,
                    real: subscription?.selected != null,
                    smart: smart, traffic: traffic),
                ),
              ]),
            ),
          ),
        ),
      );
    },
  );
}

class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('VELA', style: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 59, height: .96, letterSpacing: 5,
        color: _foreground, fontWeight: FontWeight.bold,
      )),
      SizedBox(height: 12),
      Text('— SHUO —', style: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 28, letterSpacing: 5, color: _blue,
      )),
      SizedBox(height: 33),
      Text(velaBrandTagline,
        style: TextStyle(
          color: _muted,
          fontSize: 17, height: 1.5,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w400,
        ),
      ),
    ],
  );
}

class _DemoTag extends StatelessWidget {
  const _DemoTag({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: _panel.withValues(alpha: .94),
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.visibility_outlined, color: _blue, size: 14),
      SizedBox(width: 6),
      Text(compact ? 'UI 演示' : 'UI 演示 · 尚未接入代理',
          style: TextStyle(color: _muted, fontSize: 11)),
    ]),
  );
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child, this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _panel.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        child: child,
      ),
    ),
  );
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.demo, required this.showNodes, this.compact = false,
  });
  final VelaDemoController demo;
  final VoidCallback showNodes;
  final bool compact;

  Color get statusColor => switch (demo.phase) {
    VelaPhase.connected => _mint,
    VelaPhase.error => Color(0xFFFF8B8F),
    VelaPhase.connecting || VelaPhase.switching => _blue,
    _ => _muted,
  };

  void toggle() {
    switch (demo.phase) {
      case VelaPhase.idle:
      case VelaPhase.error:
        demo.connect();
      case VelaPhase.connecting:
      case VelaPhase.switching:
      case VelaPhase.connected:
        demo.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: EdgeInsets.all(compact ? 16 : 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: compact ? 42 : 52, height: compact ? 42 : 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor.withValues(alpha: .14),
            border: Border.all(
              color: statusColor.withValues(alpha: .2),
            ),
          ),
          child: Icon(
            demo.phase == VelaPhase.error
                ? Icons.error_outline_rounded : Icons.circle,
            color: statusColor, size: compact ? 20 : 24,
          ),
        ),
        SizedBox(width: 13),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(demo.phaseText, style: TextStyle(
              fontSize: compact ? 22 : 27,
              color: statusColor, fontWeight: FontWeight.bold,
            )),
            SizedBox(height: 3),
            Text('Vela-SHUO · 连接状态演示',
                style: TextStyle(color: _muted, fontSize: 12)),
          ],
        )),
      ]),
      SizedBox(height: 18),
      Material(
        color: _blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('open_nodes'),
          borderRadius: BorderRadius.circular(12),
          onTap: showNodes,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 11, horizontal: 13,
            ),
            child: Row(children: [
              Text(demo.selected.flag,
                  style: TextStyle(fontSize: 23)),
              SizedBox(width: 10),
              Expanded(child: Text(
                '${demo.selected.country} · ${demo.selected.title}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _foreground, fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              )),
              Icon(Icons.chevron_right_rounded, color: _muted),
            ]),
          ),
        ),
      ),
      SizedBox(height: 10),
      Row(children: [
        Icon(Icons.route_outlined, size: 15, color: _muted),
        SizedBox(width: 6),
        Expanded(child: Text(
          '${demo.selected.city} · ${demo.routingMode} · 模拟节点',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: _muted),
        )),
        Text('${demo.selected.latency} ms',
            style: TextStyle(color: _mint, fontSize: 12)),
      ]),
      SizedBox(height: 15),
      SizedBox(
        height: compact ? 46 : 50,
        width: double.infinity,
        child: FilledButton.icon(
          key: ValueKey('demo_connect_button'),
          onPressed: toggle,
          icon: Icon(demo.isConnected
              ? Icons.power_settings_new_rounded : Icons.sailing_outlined),
          label: Text(
            demo.isConnected ? '断开演示连接'
                : demo.phase == VelaPhase.connecting ||
                    demo.phase == VelaPhase.switching
                    ? '取消演示' : '演示连接',
          ),
          style: FilledButton.styleFrom(
            foregroundColor: _foreground,
            backgroundColor: _blue.withValues(alpha: .23),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Color(0xFF4F9FD3)),
            ),
          ),
        ),
      ),
    ]),
  );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.demo, required this.showSmart,
    this.real = false, this.smart, this.traffic});
  final VelaDemoController demo;
  final VoidCallback showSmart;
  final bool real;
  final VelaSmartController? smart;
  final VelaTrafficMonitor? traffic;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _MetricCard(
      icon: Icons.bolt_outlined,
      label: real ? '上传速度' : '网络延迟',
      value: real
          ? VelaTrafficMonitor.rateMbps(traffic?.uploadBytesPerSecond)
          : (demo.isConnected ? demo.selected.latency.toString() : '—'),
      unit: real ? 'Mbps' : 'ms',
      caption: real ? '累计上传 ${VelaTrafficMonitor.totalLabel(traffic?.uploadedBytes)}'
          : '示意数据 · 非真实测速',
      highlight: _mint,
    )),
    SizedBox(width: 11),
    Expanded(child: _MetricCard(
      icon: Icons.download_outlined,
      label: '下载速度',
      value: real
          ? VelaTrafficMonitor.rateMbps(traffic?.downloadBytesPerSecond)
          : (demo.isConnected ? demo.selected.downloadMbps.toStringAsFixed(0) : '—'),
      unit: 'Mbps', caption: real
          ? '累计下载 ${VelaTrafficMonitor.totalLabel(traffic?.downloadedBytes)}'
          : '示意数据 · 非真实测速', highlight: _blue,
    )),
    SizedBox(width: 11),
    Expanded(child: _MetricCard(
      icon: Icons.auto_awesome_outlined,
      label: '智能模式',
      value: real ? (smart?.autoPickWhenIdle == true ? '空闲优选' : '手动优选')
          : (demo.smartEnabled ? '已启用' : '已关闭'),
      unit: '', caption: real ? '真实评分引擎 · 空闲时切换'
          : '视觉展示 · 算法尚未接入',
      highlight: _blue, onTap: showSmart,
    )),
    SizedBox(width: 11),
    Expanded(child: _MetricCard(
      icon: Icons.schedule_outlined, label: '连接时长',
      value: real ? (traffic?.elapsedLabel ?? '—') : '—', unit: '',
      caption: real ? '本次连接时长' : '演示连接不计时',
      highlight: _muted,
    )),
  ]);
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon, required this.label, required this.value,
    required this.unit, required this.caption, required this.highlight,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String caption;
  final Color highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 96,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: highlight, size: 20),
            SizedBox(width: 8),
            Flexible(child: Text(label,
              overflow: TextOverflow.ellipsis, maxLines: 1,
              style: TextStyle(color: _foreground, fontSize: 13),
            )),
          ]),
          Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: value, style: TextStyle(
                color: highlight, fontSize: 26, fontWeight: FontWeight.bold,
              )),
              TextSpan(text: unit.isEmpty ? '' : ' $unit',
                  style: TextStyle(color: _muted, fontSize: 12)),
            ])),
          ),
          SizedBox(height: 7),
          Text(caption,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _muted, fontSize: 10),
          ),
        ]),
      ),
    ),
  );
}

class _MobileHome extends StatelessWidget {
  const _MobileHome({
    required this.demo, required this.showNodes, required this.showSmart,
    this.connection, this.subscription, this.smart, this.androidVpn,
    this.traffic,
  });
  final VelaDemoController demo;
  final VelaConnectionCoordinator? connection;
  final VelaSubscriptionController? subscription;
  final VelaSmartController? smart;
  final VelaAndroidVpnController? androidVpn;
  final VelaTrafficMonitor? traffic;
  final VoidCallback showNodes;
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    children: [
      Row(children: [
        VelaBrandLogo(size: 37),
        SizedBox(width: 9),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vela-SHUO', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold,
            )),
            Text(velaBrandTagline,
              style: TextStyle(color: _muted, fontSize: 10, letterSpacing: .5),
            ),
          ],
        )),
        Platform.isAndroid ? _AndroidVpnTag(vpn: androidVpn!)
            : subscription?.selected != null ? _RealTag(compact: true)
            : _DemoTag(compact: true),
      ]),
      SizedBox(height: 7),
      SizedBox(
        height: math.min(MediaQuery.sizeOf(context).width, 400),
        child: VelaGlobe(demo: demo),
      ),
      SizedBox(height: 8),
      Platform.isAndroid
          ? _AndroidVpnCard(
              vpn: androidVpn!, subscription: subscription!,
              showNodes: showNodes)
          : subscription?.selected != null && connection != null
              ? _RealConnectionCard(connection: connection!,
                  showNodes: showNodes, compact: true)
              : _ConnectionCard(demo: demo, showNodes: showNodes, compact: true),
      SizedBox(height: 12),
      Row(children: [
        Expanded(child: _MetricCard(
          icon: Icons.upload_outlined, label: '上传速度',
          value: VelaTrafficMonitor.rateMbps(traffic?.uploadBytesPerSecond),
          unit: 'Mbps',
          caption: '累计上传 ${VelaTrafficMonitor.totalLabel(traffic?.uploadedBytes)}',
          highlight: _mint,
        )),
        SizedBox(width: 10),
        Expanded(child: _MetricCard(
          icon: Icons.download_outlined, label: '下载速度',
          value: VelaTrafficMonitor.rateMbps(traffic?.downloadBytesPerSecond),
          unit: 'Mbps',
          caption: '累计下载 ${VelaTrafficMonitor.totalLabel(traffic?.downloadedBytes)}',
          highlight: _blue,
        )),
      ]),
      SizedBox(height: 10),
      Row(children: [
        Expanded(child: _MetricCard(
          icon: Icons.auto_awesome_outlined, label: '智能模式',
          value: Platform.isAndroid ? '未启用' :
              subscription?.selected != null
              ? (smart?.autoPickWhenIdle == true ? '空闲优选' : '手动优选')
              : (demo.smartEnabled ? '已启用' : '已关闭'),
          unit: '', caption: Platform.isAndroid ? 'Android VPN Beta' :
              subscription?.selected != null
                  ? '真实评分引擎' : '引擎尚未接入',
          highlight: _blue, onTap: showSmart,
        )),
        SizedBox(width: 10),
        Expanded(child: _MetricCard(
          icon: Icons.schedule_outlined, label: '连接时长',
          value: traffic?.elapsedLabel ?? '—', unit: '',
          caption: '本次连接时长',
          highlight: _muted,
        )),
      ]),
      SizedBox(height: 20),
    ],
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
      constraints: BoxConstraints(maxWidth: 1000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 27),
        child: child,
      ),
    ),
  );
}

class _NodesPage extends StatelessWidget {
  const _NodesPage({required this.demo, required this.goHome,
    this.subscription, this.core, this.connection, this.androidVpn, this.smart});
  final VelaDemoController demo;
  final VelaSubscriptionController? subscription;
  final VelaCoreController? core;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;
  final VelaSmartController? smart;
  final VoidCallback goHome;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([demo,
      ?subscription, ?core, ?connection, ?androidVpn, ?smart]),
    builder: (context, _) => _ScreenPadding(child: ListView(children: [
      _ScreenHeading('节点', subscription?.nodes.isNotEmpty == true
          ? connection?.connected == true
              ? '在线选择 Mihomo 节点 · 验证成功后返回首页'
              : Platform.isAndroid
                  ? 'Android Mihomo VPN · 切换前请先安全断开'
                  : '来自订阅的真实节点 · 点击选择后返回首页'
          : '尚未导入订阅 · 以下是地图演示节点'),
      SizedBox(height: 18),
      Platform.isAndroid ? _AndroidVpnTag(vpn: androidVpn!) :
          subscription?.nodes.isNotEmpty == true ? _RealTag() : _DemoTag(),
      SizedBox(height: 24),
      if (subscription?.nodes.isNotEmpty == true) ...[
        if (smart != null && smart!.total > 0) ...[
          Text('最近测速：成功 ' + smart!.successful.toString() +
              ' · 失败 ' + smart!.failed.toString() +
              ' · 查看「智能优选」完整排行榜',
              style: TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 12),
        ],
        if (connection?.connected == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('在线切换使用 Mihomo Selector；新连接使用新节点，'
                '既有 TCP/UDP 连接不保证无中断。',
                style: TextStyle(color: _muted)),
          )
        else if (core?.isListening == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('当前本地代理仍在运行，请先停止手动代理。',
                style: TextStyle(color: _muted)),
          ),
        VelaNodeFilterPanel(
          controller: subscription!,
          order: smart?.sortedIndices,
          builder: (context, indices) => Column(children: [
            for (final i in indices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GlassCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: IconButton(
                  key: ValueKey('node_favorite_$i'),
                  tooltip: subscription!.isFavorite(i) ? '取消收藏' : '收藏节点',
                  onPressed: () => subscription!.toggleFavorite(i),
                  icon: Icon(subscription!.isFavorite(i)
                      ? Icons.star_rounded : Icons.star_border_rounded,
                    color: subscription!.isFavorite(i) ? _mint : _muted),
                ),
                title: Text(subscription!.nodes[i].name,
                    style: TextStyle(color: _foreground)),
                subtitle: Text(
                    smart?.downloadAt(i)?.megabytesPerSecond != null
                      ? subscription!.nodes[i].protocol + ' · ' +
                          smart!.downloadAt(i)!.megabytesPerSecond!.toStringAsFixed(2) +
                          ' MB/s · ' +
                          (smart!.resultAt(i)?.lastMs?.toString() ?? '—') + ' ms'
                      : subscription!.nodes[i].protocol,
                    style: TextStyle(color: _muted)),
                trailing: subscription!.selectedIndex == i
                    ? Icon(Icons.check_circle, color: _mint)
                    : Icon(Icons.chevron_right, color: _blue),
                onTap: androidVpn?.active == true || connection?.busy == true ||
                    (core?.isListening == true &&
                        connection?.connected != true) ? null : () async {
                  final ok = connection?.connected == true
                      ? await connection!.switchNode(i)
                      : await subscription!.selectNode(i);
                  if (ok) {
                    smart?.manualSelection();
                    goHome();
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(connection?.error ??
                          subscription!.error ?? '节点操作失败'),
                    ));
                  }
                },
              ),
            ),
          ),
          ]),
        ),
      ] else ...[
        for (final node in VelaDemoNode.samples)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: _GlassCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10,
                ),
                leading: Text(node.flag, style: TextStyle(fontSize: 29)),
                title: Text(node.country + ' · ' + node.title,
                    style: TextStyle(color: _foreground)),
                subtitle: Text(node.city + ' · 演示节点 · ' +
                    node.latency.toString() + ' ms（示意）',
                    style: TextStyle(color: _muted)),
                trailing: demo.selected.id == node.id
                    ? Icon(Icons.check_circle, color: _mint)
                    : Icon(Icons.chevron_right, color: _blue),
                onTap: () { demo.selectNode(node); goHome(); },
              ),
            ),
          ),
      ],
      SizedBox(height: 16),
      Text(subscription?.nodes.isNotEmpty == true
          ? '前往「智能优选」点击唯一的测速按钮，即可同时测全部节点的延迟与下载速度。'
          : '请前往「设置」导入订阅后选择真实节点。',
          style: TextStyle(color: _muted)),
    ])),
  );
}

class _SmartPage extends StatelessWidget {
  const _SmartPage({required this.demo, this.smart, this.subscription});
  final VelaDemoController demo;
  final VelaSmartController? smart;
  final VelaSubscriptionController? subscription;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return _ScreenPadding(child: ListView(children: [
        _ScreenHeading('智能优选', 'Android VPN Beta · 线路测速待接入'),
        const SizedBox(height: 18),
        const Text('Android Mihomo VPN · Beta'),
        const SizedBox(height: 20),
        _GlassCard(child: Text(
          'Android VpnService 和 Mihomo 原生运行层已接入。'
          '本页不会进行虚假的延迟测速、速度测试或自动节点切换。',
          style: TextStyle(color: _muted, height: 1.55),
        )),
      ]));
    }
    if (smart != null && subscription?.nodes.isNotEmpty == true) {
      return _ScreenPadding(child: ListView(children: [
        _ScreenHeading('智能优选', '真实 HTTPS 测速 · 稳定优先'),
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
      SizedBox(height: 24),
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
    required this.demo, required this.settings, this.diagnostics, this.core,
    this.subscription, this.connection, this.androidVpn,
    required this.goHome,
  });
  final VelaDemoController demo;
  final SettingsController settings;
  final VelaDiagnostics? diagnostics;
  final VelaCoreController? core;
  final VelaSubscriptionController? subscription;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;
  final VoidCallback goHome;

  @override
  Widget build(BuildContext context) => _ScreenPadding(
    child: ListView(children: [
      _ScreenHeading('设置', '为 Vela-SHUO 定义你的使用方式'),
      SizedBox(height: 18),
      Platform.isAndroid ? _AndroidVpnTag(vpn: androidVpn!) :
          subscription?.selected != null ? _RealTag() : _DemoTag(),
      SizedBox(height: 24),
      if (core != null) ...[
        if (subscription != null) ...[
          VelaSubscriptionCard(controller: subscription!, core: core!,
              androidVpn: androidVpn),
          SizedBox(height: 16),
        ],
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
          leading: Icon(Icons.info_outline, color: _blue),
          title: Text(Platform.isAndroid ? 'Vela-SHUO · Android VPN Beta'
              : 'Vela-SHUO · Windows Beta'),
          subtitle: Text(Platform.isAndroid
              ? '可授权 Android 系统 VPN；真实连接以服务状态为准'
              : '真实系统代理连接测试 · 尚非 TUN/VPN 全局代理'),
        ),
      ])),
      SizedBox(height: 16),
      _GlassCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('视觉状态预览',
              style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 7),
          Text('以下操作只改变演示状态，不会连接网络。',
              style: TextStyle(color: _muted)),
          SizedBox(height: 14),
          Wrap(spacing: 9, runSpacing: 9, children: [
            OutlinedButton(
              onPressed: () { demo.disconnect(); goHome(); },
              child: Text('未连接'),
            ),
            OutlinedButton(
              onPressed: () { demo.connect(); goHome(); },
              child: Text('演示连接'),
            ),
            OutlinedButton(
              onPressed: () { demo.simulateError(); goHome(); },
              child: Text('连接异常'),
            ),
          ]),
        ],
      )),
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
    child: Text(vpn.connected ? 'Android Mihomo VPN · 已连接'
        : 'Android Mihomo VPN · Beta',
        style: const TextStyle(fontSize: 10)),
  );
}

class _AndroidVpnCard extends StatelessWidget {
  const _AndroidVpnCard({required this.vpn, required this.subscription,
      required this.showNodes});
  final VelaAndroidVpnController vpn;
  final VelaSubscriptionController subscription;
  final VoidCallback showNodes;

  @override
  Widget build(BuildContext context) => _GlassCard(
    padding: const EdgeInsets.all(17),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.vpn_lock_rounded,
            color: vpn.connected ? _mint : _blue, size: 30),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vpn.phaseText, style: TextStyle(color: _foreground,
                fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Mihomo · Android VpnService · TUN',
                style: TextStyle(color: _muted, fontSize: 11)),
          ],
        )),
      ]),
      const SizedBox(height: 12),
      Text(subscription.selected == null
          ? '请先在设置导入订阅并选择真实节点。'
          : '已选择：${subscription.selected!.name}',
          style: TextStyle(color: _muted, fontSize: 12)),
      if (vpn.error != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(vpn.error!, style: const TextStyle(
            color: Color(0xFFE78986), fontSize: 12)),
      ),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        key: const ValueKey('android_vpn_button'),
        onPressed: vpn.busy || (!vpn.active &&
            subscription.selected == null) ? null : () async {
          if (vpn.connected) {
            await vpn.stop();
          } else {
            await vpn.start(subscription);
          }
        },
        icon: Icon(vpn.connected ? Icons.power_settings_new_rounded
            : Icons.vpn_key_rounded),
        label: Text(vpn.connected ? '安全断开 Android VPN'
            : vpn.busy ? '正在建立 VPN…' : '授权并连接真实 VPN'),
      )),
      if (vpn.connected) ...[
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          key: const ValueKey('vela_android_internet_test'),
          icon: const Icon(Icons.public),
          label: const Text('测试 VPN 真实联网'),
          onPressed: () async {
            final ok = await vpn.testConnectivity();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ok
                ? 'VPN 内真实 HTTPS 联网测试通过'
                : 'VPN 内真实 HTTPS 联网测试失败，请检查节点与 DNS'),
            ));
          },
        )),
      ],
      const SizedBox(height: 8),
      TextButton.icon(onPressed: vpn.active ? null : showNodes,
          icon: const Icon(Icons.route_outlined),
          label: const Text('选择线路')),
      Text('Beta：首次连接需要 Android VPN 授权，'
          '系统状态由原生服务和 HTTPS 验证更新。',
          style: TextStyle(color: _muted, fontSize: 11)),
    ]),
  );
}

class _RealTag extends StatelessWidget {
  const _RealTag({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 13, vertical: compact ? 5 : 8,
    ),
    decoration: BoxDecoration(
      color: _mint.withValues(alpha: .11),
      border: Border.all(color: _mint.withValues(alpha: .36)),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text('真实代理模式 · Windows 系统代理',
      style: TextStyle(color: _foreground, fontSize: compact ? 9 : 11),
    ),
  );
}

class _RealConnectionCard extends StatelessWidget {
  const _RealConnectionCard({
    required this.connection, required this.showNodes,
    this.compact = false,
  });
  final VelaConnectionCoordinator connection;
  final VoidCallback showNodes;
  final bool compact;

  Future<void> toggle(BuildContext context) async {
    if (connection.busy) return;
    if (connection.connected || connection.proxy.active) {
      await connection.disconnect();
      return;
    }
    if (!connection.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中导入订阅并选择真实节点')),
      );
      return;
    }
    // One-click after clear, explicit user consent to changing WinINet.
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('允许接管 Windows 系统代理？'),
        content: const Text(
          'Vela-SHUO 将先验证选中的节点，验证成功后才把本机 HTTP 系统代理'
          '设置为 127.0.0.1:20808。\n\n'
          '软件会保存当前代理设置并在断开时恢复；'
          '如果你正在使用其他代理软件，其设置可能暂时被替换。'
          '目前仅接管遵循 Windows 代理设置的应用，并非 VPN/TUN 全局代理。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('允许并连接'),
          ),
        ],
      ),
    );
    if (consent == true) await connection.connect();
  }

  @override
  Widget build(BuildContext context) {
    final color = connection.connected ? _mint :
        connection.phase == VelaRealPhase.error
            ? const Color(0xFFE78986) : _blue;
    final estimated = VelaDemoNode.approximateFromName(connection.nodeName);
    return _GlassCard(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.language_rounded, color: color,
                size: compact ? 32 : 42),
            const SizedBox(width: 13),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(connection.phaseText, style: TextStyle(
                  color: color, fontWeight: FontWeight.bold,
                  fontSize: compact ? 21 : 26,
                )),
                Text('Mihomo · 真实线路与系统代理',
                    style: TextStyle(color: _muted, fontSize: 12)),
              ],
            )),
          ]),
          const SizedBox(height: 13),
          Material(
            color: _blue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              dense: true,
              onTap: connection.busy ? null : showNodes,
              leading: Icon(Icons.route_outlined, color: _blue),
              title: Text(connection.nodeName, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _foreground)),
              trailing: Icon(Icons.chevron_right, color: _muted),
            ),
          ),
          const SizedBox(height: 8),
          Text(estimated == null
              ? '节点地理位置未知，地球保持原视角'
              : '地球航线位置由节点名称估算 · 非 IP 定位',
            style: TextStyle(fontSize: 11, color: _muted),
          ),
          if (connection.error != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(connection.error!, maxLines: 3,
              style: const TextStyle(color: Color(0xFFE78986), fontSize: 11)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: compact ? 44 : 48,
            child: FilledButton.icon(
              key: const ValueKey('real_connect_button'),
              onPressed: connection.busy ? null : () => toggle(context),
              icon: Icon(connection.connected || connection.proxy.active
                  ? Icons.power_settings_new_rounded : Icons.sailing_outlined),
              label: Text(connection.busy ? '请稍候…' :
                  connection.connected || connection.proxy.active
                      ? '安全断开并恢复代理' : '连接所选真实节点'),
              style: FilledButton.styleFrom(
                backgroundColor: _blue.withValues(alpha: .26),
                foregroundColor: _foreground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _blue),
                ),
              ),
            ),
          ),
          if (connection.connected || connection.core.isListening) ...[
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              key: const ValueKey('vela_real_internet_test'),
              icon: const Icon(Icons.public),
              label: const Text('测试当前节点联网'),
              onPressed: connection.busy || connection.core.probing ? null : () async {
                final ok = await connection.core.verifyRemote();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                    ? '真实 HTTPS 联网测试通过：当前节点可以访问外网'
                    : '真实 HTTPS 联网测试失败：请检查节点或订阅'),
                ));
              },
            )),
          ],
        ],
      ),
    );
  }
}
