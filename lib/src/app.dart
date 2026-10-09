import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vela_shuo/src/home/demo_connection.dart';
import 'package:vela_shuo/src/home/globe.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

const _background = Color(0xFF06111F);
const _panel = Color(0xFF0D1D30);
const _line = Color(0xFF2A4863);
const _blue = Color(0xFF80C7F8);
const _muted = Color(0xFF97AEC4);
const _mint = Color(0xFF63E6B7);

class VelaShuoApp extends StatelessWidget {
  const VelaShuoApp({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) => MaterialApp(
      title: 'Vela-SHUO',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: _Shell(settings: settings),
    ),
  );
}

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _blue,
    brightness: brightness,
    surface: dark ? _background : const Color(0xFFF1F5FA),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? _panel : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.settings});
  final SettingsController settings;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final VelaDemoController demo = VelaDemoController();
  int tab = 0;

  static const destinations = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, '首页'),
    (Icons.language_outlined, Icons.language_rounded, '节点'),
    (Icons.auto_graph_outlined, Icons.auto_graph_rounded, '智能优选'),
    (Icons.settings_outlined, Icons.settings_rounded, '设置'),
  ];

  @override
  void dispose() {
    demo.dispose();
    super.dispose();
  }

  void navigate(int i) => setState(() => tab = i);

  Widget page(bool desktop) => switch (tab) {
    1 => _NodesPage(demo: demo, goHome: () => navigate(0)),
    2 => _SmartPage(demo: demo),
    3 => _SettingsPage(
      demo: demo, settings: widget.settings, goHome: () => navigate(0),
    ),
    _ => _HomePage(
      demo: demo, desktop: desktop,
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [_background, Color(0xFF0B2038), _background],
            ),
          ),
          child: SafeArea(
            child: Row(children: [
              if (desktop)
                Container(
                  width: extended ? 190 : 90,
                  decoration: const BoxDecoration(
                    color: Color(0xCC06121F),
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
          decoration: const BoxDecoration(
            color: Color(0xFF0B1A2B),
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
    const SizedBox(height: 32),
    const VelaBrandLogo(size: 68),
    if (extended) ...[
      const SizedBox(height: 8),
      const Text('VELA', style: TextStyle(
        color: Colors.white, fontSize: 21,
        letterSpacing: 3, fontWeight: FontWeight.w700,
      )),
      const Text('— SHUO —', style: TextStyle(
        color: _blue, fontSize: 12, letterSpacing: 2,
      )),
      const SizedBox(height: 6),
      const Text('INTELLIGENT CONNECTIVITY',
        style: TextStyle(color: _muted, fontSize: 7, letterSpacing: 1),
      ),
    ],
    const SizedBox(height: 46),
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
                  if (extended) const SizedBox(width: 15),
                  Icon(
                    selected == i
                        ? _ShellState.destinations[i].$2
                        : _ShellState.destinations[i].$1,
                    color: selected == i ? _blue : _muted, size: 22,
                  ),
                  if (extended) ...[
                    const SizedBox(width: 15),
                    Text(_ShellState.destinations[i].$3,
                      style: TextStyle(
                        color: selected == i ? Colors.white : _muted,
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
    const Spacer(),
    if (extended) ...[
      const Text('更自由的连接世界',
        style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1),
      ),
      const SizedBox(height: 25),
    ],
  ]);
}

class VelaBrandLogo extends StatelessWidget {
  const VelaBrandLogo({super.key, this.size = 65});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * .75),
    painter: const _SailLogoPainter(),
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
      ..shader = const LinearGradient(
        colors: [Color(0xFFB7E7FF), Color(0xFF448DBF)],
      ).createShader(Offset.zero & size));
    canvas.drawPath(right, Paint()..color = const Color(0xFF8DBCD8));
    final hull = Path()
      ..moveTo(w * .1, h * .88)
      ..quadraticBezierTo(w * .52, h * 1.03, w * .94, h * .88);
    canvas.drawPath(hull, Paint()
      ..color = const Color(0xFFB7E7FF)
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
  });
  final VelaDemoController demo;
  final bool desktop;
  final VoidCallback showNodes;
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: demo,
    builder: (context, _) => desktop
      ? _DesktopHome(
          demo: demo, showNodes: showNodes, showSmart: showSmart,
        )
      : _MobileHome(
          demo: demo, showNodes: showNodes, showSmart: showSmart,
        ),
  );
}

class _DesktopHome extends StatelessWidget {
  const _DesktopHome({
    required this.demo, required this.showNodes, required this.showSmart,
  });
  final VelaDemoController demo;
  final VoidCallback showNodes;
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = math.max(790.0, constraints.maxHeight);
      final contentWidth = math.min(width - 40, 1320.0);
      final globeSize = math.min(width * .95, height * 1.34);
      return SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: contentWidth, height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                top: -globeSize * .16,
                right: -globeSize * .12,
                width: globeSize, height: globeSize,
                child: IgnorePointer(child: VelaGlobe(demo: demo)),
              ),
              const Positioned(top: 20, right: 4, child: _DemoTag()),
              const Positioned(left: 22, top: 69, child: _HeroIdentity()),
              Positioned(
                left: 18,
                top: height * .45,
                width: math.min(contentWidth * .47, 520),
                child: _ConnectionCard(demo: demo, showNodes: showNodes),
              ),
              Positioned(
                left: 12, right: 12, bottom: 22,
                child: _Stats(demo: demo, showSmart: showSmart),
              ),
            ]),
          ),
        ),
      );
    },
  );
}

class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('更 自 由 的 连 接 世 界',
          style: TextStyle(color: _muted, fontSize: 12, letterSpacing: 2)),
      SizedBox(height: 16),
      Text('VELA', style: TextStyle(
        fontSize: 59, height: .96, letterSpacing: 5,
        color: Color(0xFFF2F8FF), fontWeight: FontWeight.bold,
      )),
      SizedBox(height: 10),
      Text('— SHUO —', style: TextStyle(
        fontSize: 28, letterSpacing: 5, color: _blue,
      )),
      SizedBox(height: 10),
      Text('INTELLIGENT CONNECTIVITY',
          style: TextStyle(color: _muted, fontSize: 11, letterSpacing: 2)),
      SizedBox(height: 25),
      Text('智能路由，畅行全球\n让重要的连接，更简单。',
          style: TextStyle(
            color: Color(0xFFB1C6DC), fontSize: 15, height: 1.8,
          )),
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
      color: const Color(0xEA0D2337),
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.visibility_outlined, color: _blue, size: 14),
      const SizedBox(width: 6),
      Text(compact ? 'UI 演示' : 'UI 演示 · 尚未接入代理',
          style: const TextStyle(color: _muted, fontSize: 11)),
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
          color: const Color(0xDB0B1E33),
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
    VelaPhase.error => const Color(0xFFFF8B8F),
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
        const SizedBox(width: 13),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(demo.phaseText, style: TextStyle(
              fontSize: compact ? 22 : 27,
              color: statusColor, fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 3),
            const Text('Vela-SHUO · 连接状态演示',
                style: TextStyle(color: _muted, fontSize: 12)),
          ],
        )),
      ]),
      const SizedBox(height: 18),
      Material(
        color: _blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('open_nodes'),
          borderRadius: BorderRadius.circular(12),
          onTap: showNodes,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 11, horizontal: 13,
            ),
            child: Row(children: [
              Text(demo.selected.flag,
                  style: const TextStyle(fontSize: 23)),
              const SizedBox(width: 10),
              Expanded(child: Text(
                '${demo.selected.country} · ${demo.selected.title}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              )),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        const Icon(Icons.route_outlined, size: 15, color: _muted),
        const SizedBox(width: 6),
        Expanded(child: Text(
          '${demo.selected.city} · ${demo.routingMode} · 模拟节点',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: _muted),
        )),
        Text('${demo.selected.latency} ms',
            style: const TextStyle(color: _mint, fontSize: 12)),
      ]),
      const SizedBox(height: 15),
      SizedBox(
        height: compact ? 46 : 50,
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('demo_connect_button'),
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
            foregroundColor: Colors.white,
            backgroundColor: _blue.withValues(alpha: .23),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF4F9FD3)),
            ),
          ),
        ),
      ),
    ]),
  );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.demo, required this.showSmart});
  final VelaDemoController demo;
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _MetricCard(
      icon: Icons.bolt_outlined,
      label: '网络延迟',
      value: demo.isConnected ? demo.selected.latency.toString() : '—',
      unit: 'ms', caption: '示意数据 · 非真实测速', highlight: _mint,
    )),
    const SizedBox(width: 11),
    Expanded(child: _MetricCard(
      icon: Icons.download_outlined,
      label: '下载速度',
      value: demo.isConnected
          ? demo.selected.downloadMbps.toStringAsFixed(0) : '—',
      unit: 'Mbps', caption: '示意数据 · 非真实测速', highlight: _blue,
    )),
    const SizedBox(width: 11),
    Expanded(child: _MetricCard(
      icon: Icons.auto_awesome_outlined,
      label: '智能模式',
      value: demo.smartEnabled ? '已启用' : '已关闭',
      unit: '', caption: '视觉展示 · 算法尚未接入',
      highlight: _blue, onTap: showSmart,
    )),
    const SizedBox(width: 11),
    const Expanded(child: _MetricCard(
      icon: Icons.schedule_outlined, label: '连接时长',
      value: '—', unit: '', caption: '真实连接后显示计时',
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
            const SizedBox(width: 8),
            Flexible(child: Text(label,
              overflow: TextOverflow.ellipsis, maxLines: 1,
              style: const TextStyle(color: Color(0xFFCEDFED), fontSize: 13),
            )),
          ]),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: value, style: TextStyle(
                color: highlight, fontSize: 26, fontWeight: FontWeight.bold,
              )),
              TextSpan(text: unit.isEmpty ? '' : ' $unit',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ])),
          ),
          const SizedBox(height: 7),
          Text(caption,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ]),
      ),
    ),
  );
}

class _MobileHome extends StatelessWidget {
  const _MobileHome({
    required this.demo, required this.showNodes, required this.showSmart,
  });
  final VelaDemoController demo;
  final VoidCallback showNodes;
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    children: [
      Row(children: [
        const VelaBrandLogo(size: 37),
        const SizedBox(width: 9),
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vela-SHUO', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold,
            )),
            Text('INTELLIGENT CONNECTIVITY',
              style: TextStyle(color: _muted, fontSize: 8, letterSpacing: 1),
            ),
          ],
        )),
        const _DemoTag(compact: true),
      ]),
      const SizedBox(height: 7),
      SizedBox(
        height: math.min(MediaQuery.sizeOf(context).width, 400),
        child: VelaGlobe(demo: demo),
      ),
      const SizedBox(height: 8),
      _ConnectionCard(demo: demo, showNodes: showNodes, compact: true),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _MetricCard(
          icon: Icons.bolt_outlined, label: '网络延迟',
          value: demo.isConnected ? demo.selected.latency.toString() : '—',
          unit: 'ms', caption: '示意数据', highlight: _mint,
        )),
        const SizedBox(width: 10),
        Expanded(child: _MetricCard(
          icon: Icons.download_outlined, label: '下载速度',
          value: demo.isConnected
              ? demo.selected.downloadMbps.toStringAsFixed(0) : '—',
          unit: 'Mbps', caption: '示意数据', highlight: _blue,
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _MetricCard(
          icon: Icons.auto_awesome_outlined, label: '智能模式',
          value: demo.smartEnabled ? '已启用' : '已关闭',
          unit: '', caption: '引擎尚未接入',
          highlight: _blue, onTap: showSmart,
        )),
        const SizedBox(width: 10),
        const Expanded(child: _MetricCard(
          icon: Icons.schedule_outlined, label: '连接时长',
          value: '—', unit: '', caption: '后续版本开放',
          highlight: _muted,
        )),
      ]),
      const SizedBox(height: 20),
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
      Text(title, style: const TextStyle(
        color: Colors.white, fontSize: 29, fontWeight: FontWeight.bold,
      )),
      const SizedBox(height: 7),
      Text(subtitle, style: const TextStyle(color: _muted)),
    ],
  );
}

class _ScreenPadding extends StatelessWidget {
  const _ScreenPadding({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 27),
        child: child,
      ),
    ),
  );
}

class _NodesPage extends StatelessWidget {
  const _NodesPage({required this.demo, required this.goHome});
  final VelaDemoController demo;
  final VoidCallback goHome;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: demo,
    builder: (context, _) => _ScreenPadding(child: ListView(children: [
      const _ScreenHeading('节点', '选择目的地 · 预览地球转向的交互效果'),
      const SizedBox(height: 18),
      const _DemoTag(),
      const SizedBox(height: 24),
      for (final node in VelaDemoNode.samples)
        Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: _GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10,
              ),
              leading: Text(node.flag,
                style: const TextStyle(fontSize: 29),
              ),
              title: Text('${node.country} · ${node.title}',
                style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                '${node.city} · 演示节点 · ${node.latency} ms（示意）',
                style: const TextStyle(color: _muted),
              ),
              trailing: demo.selected.id == node.id
                  ? const Icon(Icons.check_circle, color: _mint)
                  : const Icon(Icons.chevron_right, color: _blue),
              onTap: () { demo.selectNode(node); goHome(); },
            ),
          ),
        ),
      const SizedBox(height: 16),
      const Text('订阅导入和真实节点测速将随代理内核在后续版本实现。',
          style: TextStyle(color: _muted)),
    ])),
  );
}

class _SmartPage extends StatelessWidget {
  const _SmartPage({required this.demo});
  final VelaDemoController demo;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: demo,
    builder: (context, _) => _ScreenPadding(child: ListView(children: [
      const _ScreenHeading('智能优选', '稳定优先 · 让每一次连接更从容'),
      const SizedBox(height: 18),
      const _DemoTag(),
      const SizedBox(height: 24),
      _GlassCard(child: Column(children: [
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome, color: _blue),
          title: const Text('智能优选（界面演示）'),
          subtitle: const Text('暂不执行测速或自动切换'),
          value: demo.smartEnabled,
          onChanged: demo.setSmart,
        ),
        const Divider(color: _line, height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.shield_outlined, color: _blue),
          title: const Text('活跃连接保护（界面演示）'),
          subtitle: const Text('真实保护功能将在内核接入后实现'),
          value: demo.protectConnections,
          onChanged: demo.setProtection,
        ),
      ])),
      const SizedBox(height: 17),
      const _GlassCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SHUO Smart Engine',
              style: TextStyle(
                color: Colors.white, fontSize: 19,
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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.demo, required this.settings, required this.goHome,
  });
  final VelaDemoController demo;
  final SettingsController settings;
  final VoidCallback goHome;

  @override
  Widget build(BuildContext context) => _ScreenPadding(
    child: ListView(children: [
      const _ScreenHeading('设置', '为 Vela-SHUO 定义你的使用方式'),
      const SizedBox(height: 18),
      const _DemoTag(),
      const SizedBox(height: 24),
      _GlassCard(child: Column(children: [
        ListTile(
          leading: const Icon(Icons.palette_outlined, color: _blue),
          title: const Text('外观主题'),
          subtitle: const Text('设置自动保存'),
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
        const Divider(height: 1, color: _line),
        const ListTile(
          leading: Icon(Icons.info_outline, color: _blue),
          title: Text('Vela-SHUO v0.1.0'),
          subtitle: Text('原创首页 UI 预览 · 无真实代理连接'),
        ),
      ])),
      const SizedBox(height: 16),
      _GlassCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('视觉状态预览',
              style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          const Text('以下操作只改变演示状态，不会连接网络。',
              style: TextStyle(color: _muted)),
          const SizedBox(height: 14),
          Wrap(spacing: 9, runSpacing: 9, children: [
            OutlinedButton(
              onPressed: () { demo.disconnect(); goHome(); },
              child: const Text('未连接'),
            ),
            OutlinedButton(
              onPressed: () { demo.connect(); goHome(); },
              child: const Text('演示连接'),
            ),
            OutlinedButton(
              onPressed: () { demo.simulateError(); goHome(); },
              child: const Text('连接异常'),
            ),
          ]),
        ],
      )),
      const SizedBox(height: 16),
      const _GlassCard(child: ListTile(
        leading: Icon(Icons.privacy_tip_outlined, color: _blue),
        title: Text('隐私与安全'),
        subtitle: Text('当前原型不申请 VPN 权限，不上传遥测数据。',
            style: TextStyle(color: _muted)),
      )),
    ]),
  );
}
