// Vela-SHUO original home compositions ported from lib/src/app.dart.
// Cosmetic home layout is Vela-owned; real state/actions are FlClash-owned.
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'home/demo_connection.dart';
import 'home/globe.dart';
import 'theme/vela_palettes.dart';

Color get _background => VelaThemeRuntime.active.background;
Color get _panel => VelaThemeRuntime.active.surface;
Color get _line => VelaThemeRuntime.active.line;
Color get _blue => VelaThemeRuntime.active.accent;
Color get _muted => VelaThemeRuntime.active.muted;
Color get _mint => VelaThemeRuntime.active.accentSoft;
Color get _foreground => VelaThemeRuntime.active.text;
const velaBrandTagline = '一帆越洋，尽览四方。';

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



/// Original Vela desktop/mobile layout; state and buttons come from FlClash.
/// No sample-node connection timer or secondary proxy engine is used.
class VelaOriginalHome extends ConsumerStatefulWidget {
  const VelaOriginalHome({super.key, required this.showNodes,
    required this.showSmart});
  final VoidCallback showNodes;
  final VoidCallback showSmart;

  @override
  ConsumerState<VelaOriginalHome> createState() => _VelaOriginalHomeState();
}

class _VelaOriginalHomeState extends ConsumerState<VelaOriginalHome> {
  final VelaDemoController animation = VelaDemoController();

  @override
  void initState() {
    super.initState();
    ref.listenManual(isStartProvider, (_, _) => _sync(),
        fireImmediately: true);
    ref.listenManual(coreStatusProvider, (_, _) => _sync());
    ref.listenManual(suspendProvider, (_, _) => _sync());
    ref.listenManual(currentProfileProvider, (_, _) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    final running = ref.read(isStartProvider);
    final suspended = ref.read(suspendProvider);
    final core = ref.read(coreStatusProvider);
    final profile = ref.read(currentProfileProvider);
    final names = profile?.selectedMap.values;
    final nodeName = names != null && names.isNotEmpty ? names.first : null;
    final phase = !running || suspended ? VelaPhase.idle
      : core == CoreStatus.connected ? VelaPhase.connected
      : core == CoreStatus.connecting ? VelaPhase.connecting
      : VelaPhase.error;
    animation.projectRealState(phase, nodeName);
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 820;
    return desktop
      ? _desktop()
      : _mobile();
  }

  Widget _desktop() => LayoutBuilder(builder: (context, constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final designWidth = math.max(820.0, math.min(width - 24, 1320.0));
    const designHeight = 760.0;
    final globeSize = math.min(designWidth * .94, 960.0);

    return Center(child: SizedBox(
      width: width, height: height,
      child: FittedBox(fit: BoxFit.contain, alignment: Alignment.center,
        child: SizedBox(
          width: designWidth, height: designHeight,
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned(
              top: -globeSize * .16, right: -globeSize * .10,
              width: globeSize, height: globeSize,
              child: IgnorePointer(child: VelaGlobe(demo: animation)),
            ),
            const Positioned(top: 20, right: 12, child: _RealTag()),
            const Positioned(left: 22, top: 62, child: _HeroIdentity()),
            Positioned(
              left: 18, top: 318,
              width: math.min(designWidth * .47, 520.0),
              child: _FlClashConnectionCard(showNodes: widget.showNodes)),
            Positioned(left: 12, right: 12, bottom: 18,
              child: _StatsRow(showSmart: widget.showSmart)),
          ]),
        ),
      ),
    ));
  });

  Widget _mobile() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    children: [
      Row(children: [
        const VelaBrandLogo(size: 37),
        const SizedBox(width: 9),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vela-SHUO', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold)),
            Text(velaBrandTagline, style: TextStyle(
              color: _muted, fontSize: 10, letterSpacing: .5)),
          ],
        )),
        const _RealTag(compact: true),
      ]),
      const SizedBox(height: 7),
      SizedBox(
        height: math.min(MediaQuery.sizeOf(context).width, 400),
        child: VelaGlobe(demo: animation),
      ),
      const SizedBox(height: 8),
      _FlClashConnectionCard(
        showNodes: widget.showNodes, compact: true),
      const SizedBox(height: 12),
      _MetricsPair(first: true),
      const SizedBox(height: 10),
      _MetricsPair(first: false, showSmart: widget.showSmart),
      const SizedBox(height: 20),
    ],
  );
}

class _RealTag extends StatelessWidget {
  const _RealTag({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 13, vertical: compact ? 5 : 8),
    decoration: BoxDecoration(
      color: _mint.withValues(alpha: .11),
      border: Border.all(color: _mint.withValues(alpha: .36)),
      borderRadius: BorderRadius.circular(30)),
    child: Text('Vela-SHUO · 真实内核',
      style: TextStyle(color: _foreground,
        fontSize: compact ? 9 : 11)),
  );
}

/// Keep the exact Vela connection card shape; only swap network callbacks.
class _FlClashConnectionCard extends ConsumerWidget {
  const _FlClashConnectionCard({
    required this.showNodes, this.compact = false,
  });
  final VoidCallback showNodes;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(isStartProvider);
    final suspended = ref.watch(suspendProvider);
    final status = ref.watch(coreStatusProvider);
    final profile = ref.watch(currentProfileProvider);
    final selected = profile?.selectedMap.values;
    final name = selected != null && selected.isNotEmpty
      ? selected.first : '未选择节点';
    final error = running && !suspended && status != CoreStatus.connected
      && status != CoreStatus.connecting;
    final color = error ? const Color(0xFFE78986)
      : running && !suspended ? _mint : _blue;
    final title = !running ? '未启用连接' : suspended ? '已暂停'
      : status == CoreStatus.connected ? '已连接'
      : status == CoreStatus.connecting ? '正在连接…'
      : '连接异常';
    final approximate = VelaDemoNode.approximateFromName(name);
    return _GlassCard(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.language_rounded, color: color,
              size: compact ? 32 : 42),
            const SizedBox(width: 13),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  color: color, fontWeight: FontWeight.bold,
                  fontSize: compact ? 21 : 26)),
                Text('Vela-SHUO · 真实代理连接',
                  style: TextStyle(color: _muted, fontSize: 12)),
              ],
            )),
          ]),
          const SizedBox(height: 13),
          Material(color: _blue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              dense: true,
              onTap: showNodes,
              leading: Icon(Icons.route_outlined, color: _blue),
              title: Text(name, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _foreground)),
              trailing: Icon(Icons.chevron_right, color: _muted),
            ),
          ),
          const SizedBox(height: 8),
          Text(approximate == null
            ? '节点地理位置未知，地球保持原视角'
            : '地球航线由节点名称估算 · 非 IP 定位',
            style: TextStyle(fontSize: 11, color: _muted)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: compact ? 44 : 48,
            child: FilledButton.icon(
              key: const ValueKey('vela_real_connect'),
              onPressed: profile == null ? null
                : () => ref.read(commonActionProvider.notifier).toggleRunning(),
              icon: Icon(running ? Icons.power_settings_new_rounded
                : Icons.sailing_outlined),
              label: Text(profile == null ? '请先导入订阅'
                : running ? '安全断开连接' : '连接所选真实节点'),
              style: FilledButton.styleFrom(
                backgroundColor: _blue.withValues(alpha: .26),
                foregroundColor: _foreground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _blue)),
              ),
            ),
          ),
        ]),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.showSmart});
  final VoidCallback showSmart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(totalTrafficProvider);
    final running = ref.watch(isStartProvider);
    return Row(children: [
      Expanded(child: _MetricCard(
        icon: Icons.bolt_outlined, label: '上传速度',
        value: running ? (traffic.up * 8 / 1000000).toStringAsFixed(2) : '—',
        unit: 'Mbps', caption: '当前连接实时上传', highlight: _mint)),
      const SizedBox(width: 11),
      Expanded(child: _MetricCard(
        icon: Icons.download_outlined, label: '下载速度',
        value: running ? (traffic.down * 8 / 1000000).toStringAsFixed(2) : '—',
        unit: 'Mbps', caption: '当前连接实时下载', highlight: _blue)),
      const SizedBox(width: 11),
      Expanded(child: _MetricCard(
        icon: Icons.auto_awesome_outlined, label: '智能模式',
        value: '手动优选', unit: '',
        caption: '真实测速 · 不显示模拟成绩',
        highlight: _blue, onTap: showSmart)),
      const SizedBox(width: 11),
      Expanded(child: _MetricCard(
        icon: Icons.schedule_outlined, label: '连接时长',
        value: running ? '运行中' : '—', unit: '',
        caption: '以后台连接状态为准', highlight: _muted)),
    ]);
  }
}

class _MetricsPair extends ConsumerWidget {
  const _MetricsPair({required this.first, this.showSmart});
  final bool first;
  final VoidCallback? showSmart;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(isStartProvider);
    final traffic = ref.watch(totalTrafficProvider);
    if (first) {
      return Row(children: [
        Expanded(child: _MetricCard(
          icon: Icons.upload_outlined, label: '上传速度',
          value: running ? (traffic.up * 8 / 1000000).toStringAsFixed(2) : '—',
          unit: 'Mbps', caption: '当前实时上传', highlight: _mint)),
        const SizedBox(width: 10),
        Expanded(child: _MetricCard(
          icon: Icons.download_outlined, label: '下载速度',
          value: running ? (traffic.down * 8 / 1000000).toStringAsFixed(2) : '—',
          unit: 'Mbps', caption: '当前实时下载', highlight: _blue)),
      ]);
    }
    return Row(children: [
      Expanded(child: _MetricCard(
        icon: Icons.auto_awesome_outlined, label: '智能模式',
        value: '手动优选', unit: '',
        caption: '真实测速', highlight: _blue,
        onTap: showSmart)),
      const SizedBox(width: 10),
      Expanded(child: _MetricCard(
        icon: Icons.schedule_outlined, label: '连接时长',
        value: running ? '运行中' : '—', unit: '',
        caption: '本次连接', highlight: _muted)),
    ]);
  }
}
