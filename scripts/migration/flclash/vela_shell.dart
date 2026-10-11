import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/vela_shuo/theme/vela_palettes.dart';
import 'vela_flight_header.dart';

/// The user-facing application. FlClash owns the backend through Riverpod.
/// No FlClash view, scaffold, navigator or settings screen is mounted here.
class VelaShell extends ConsumerStatefulWidget {
  const VelaShell({super.key});

  @override
  ConsumerState<VelaShell> createState() => _VelaShellState();
}

class _VelaShellState extends ConsumerState<VelaShell> {
  int tab = 0;
  String query = '';
  String paletteId = VelaPalette.defaultId;

  static const labels = ['首页', '节点', '智能优选', '设置'];
  static const normalIcons = [
    Icons.home_outlined,
    Icons.language_outlined,
    Icons.auto_graph_outlined,
    Icons.settings_outlined,
  ];
  static const selectedIcons = [
    Icons.home_rounded,
    Icons.language_rounded,
    Icons.auto_graph_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    VelaThemeRuntime.select(VelaPalette.byId(paletteId), Theme.of(context).brightness);
    final t = VelaThemeRuntime.active;
    final desktop = MediaQuery.sizeOf(context).width >= 820;
    final extended = MediaQuery.sizeOf(context).width >= 1250;
    final pages = [_home(), _nodes(), _smart(), _settings()];
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: t.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: t.dark ? Brightness.dark : Brightness.light,
          surface: t.background,
        ),
      ),
      child: Scaffold(
        backgroundColor: t.background,
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.background, t.raised, t.background],
          )),
          child: SafeArea(child: Row(children: [
            if (desktop) _desktopNav(extended),
            Expanded(child: pages[tab]),
          ])),
        ),
        bottomNavigationBar: desktop ? null : Container(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.line)),
          ),
          child: NavigationBar(
            height: 68,
            backgroundColor: Colors.transparent,
            indicatorColor: t.accent.withValues(alpha: .15),
            selectedIndex: tab,
            onDestinationSelected: (index) => setState(() => tab = index),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (var i = 0; i < labels.length; i++)
                NavigationDestination(
                  icon: Icon(normalIcons[i], color: t.muted),
                  selectedIcon: Icon(selectedIcons[i], color: t.accent),
                  label: labels[i],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopNav(bool extended) {
    final t = VelaThemeRuntime.active;
    return Container(
      width: extended ? 190 : 90,
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: .84),
        border: Border(right: BorderSide(color: t.line)),
      ),
      child: Column(children: [
        const SizedBox(height: 30),
        const VelaBrandLogo(size: 68),
        if (extended) ...[
          const SizedBox(height: 8),
          Text('VELA', style: TextStyle(color: t.text, fontSize: 21,
            letterSpacing: 3, fontWeight: FontWeight.w700)),
          Text('— SHUO —', style: TextStyle(color: t.accent,
            fontSize: 12, letterSpacing: 2)),
        ],
        const SizedBox(height: 46),
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Material(
              color: tab == i ? t.accent.withValues(alpha: .15) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                key: ValueKey('vela_nav_' + i.toString()),
                onTap: () => setState(() => tab = i),
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(height: 52, child: Row(
                  mainAxisAlignment: extended
                    ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    if (extended) const SizedBox(width: 15),
                    Icon(tab == i ? selectedIcons[i] : normalIcons[i],
                      color: tab == i ? t.accent : t.muted, size: 22),
                    if (extended) ...[
                      const SizedBox(width: 15),
                      Text(labels[i], style: TextStyle(
                        color: tab == i ? t.text : t.muted,
                        fontWeight: tab == i ? FontWeight.w600 : FontWeight.normal,
                      )),
                    ],
                  ],
                )),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _page(String title, List<Widget> children) {
    final t = VelaThemeRuntime.active;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
      children: [
        Text(title, style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold,
          color: t.text, letterSpacing: .5)),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }

  Widget _card(Widget content) {
    final t = VelaThemeRuntime.active;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.line),
      ),
      child: content,
    );
  }

  Widget _subtitle(String text) => Text(text, style:
    TextStyle(fontSize: 13, color: VelaThemeRuntime.active.muted));

  Widget _home() {
    final t = VelaThemeRuntime.active;
    final running = ref.watch(isStartProvider);
    final status = ref.watch(coreStatusProvider);
    final profile = ref.watch(currentProfileProvider);
    final suspended = ref.watch(suspendProvider);
    final label = !running ? '等待启航' : suspended ? '已暂停'
      : status == CoreStatus.connected ? '已连接'
      : status == CoreStatus.connecting ? '正在连接' : '连接异常';
    return _page('一帆越洋，尽览四方。', [
      const VelaFlightHeader(),
      const SizedBox(height: 18),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: t.accent,
          fontWeight: FontWeight.bold, fontSize: 23)),
        const SizedBox(height: 8),
        _subtitle(profile == null ? '请先在设置中导入订阅' : '当前订阅：' + profile.realLabel),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, height: 48,
          child: FilledButton.icon(
            key: const ValueKey('vela_real_connect'),
            onPressed: profile == null ? null
              : () => ref.read(commonActionProvider.notifier).toggleRunning(),
            icon: Icon(running ? Icons.power_settings_new : Icons.sailing),
            label: Text(running ? '断开连接' : '启航连接'),
          ),
        ),
      ])),
      Row(children: [
        Expanded(child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [Icon(Icons.language, color: t.accent),
            const SizedBox(height: 9), _subtitle('节点管理'),
            const SizedBox(height: 6),
            TextButton(onPressed: () => setState(() => tab = 1),
              child: const Text('选择节点 →'))]))),
        const SizedBox(width: 12),
        Expanded(child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [Icon(Icons.tune, color: t.accent),
            const SizedBox(height: 9), _subtitle('订阅和设置'),
            const SizedBox(height: 6),
            TextButton(onPressed: () => setState(() => tab = 3),
              child: const Text('前往设置 →'))]))),
      ]),
    ]);
  }

  Widget _nodes() {
    final t = VelaThemeRuntime.active;
    final groups = ref.watch(visibleGroupsStateProvider).value;
    final selected = ref.watch(currentProfileProvider)?.selectedMap ?? <String, String>{};
    final results = groups.map((g) => (group: g,
      proxies: g.all.where((p) => p.name.toLowerCase().contains(query.toLowerCase())).toList()))
      .where((entry) => entry.proxies.isNotEmpty).toList();
    return _page('节点', [
      TextField(
        key: const ValueKey('vela_node_search'),
        onChanged: (value) => setState(() => query = value),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '搜索节点名称',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      if (groups.isEmpty) _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('还没有可用节点'),
          _subtitle('请先添加订阅并连接内核。'),
          TextButton(onPressed: () => setState(() => tab = 3),
            child: const Text('前往订阅管理')),
        ],
      )),
      for (final entry in results)
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.group.name, style: TextStyle(
            color: t.text, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final proxy in entry.proxies)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(proxy.name, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.text)),
              leading: Icon(selected[entry.group.name] == proxy.name
                ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected[entry.group.name] == proxy.name ? t.accent : t.muted),
              onTap: () => ref.read(proxiesActionProvider.notifier).changeProxy(
                groupName: entry.group.name, proxyName: proxy.name),
            ),
        ])),
    ]);
  }

  Widget _smart() {
    final t = VelaThemeRuntime.active;
    final groups = ref.watch(visibleGroupsStateProvider).value;
    final running = ref.watch(isStartProvider);
    return _page('智能优选', [
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('节点延迟检测', style: TextStyle(color: t.text,
          fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _subtitle('对真实节点执行延迟测试，不展示模拟成绩。'),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: !running || groups.isEmpty ? null
            : () => ref.read(proxiesActionProvider.notifier).delayTestGroups(groups),
          icon: const Icon(Icons.bolt),
          label: const Text('检测所有节点'),
        )),
        const SizedBox(height: 8),
        _subtitle('旧 Vela 独立测速器不再运行。'),
      ])),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('优选状态', style: TextStyle(color: t.text,
          fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        _subtitle('自动速度优选、定时切换须在 FlClash 数据层完成适配，'
          '在实现前不会伪装成已启用。'),
      ])),
    ]);
  }

  Widget _settings() {
    final t = VelaThemeRuntime.active;
    final state = ref.watch(profilesStateProvider);
    return _page('设置', [
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('订阅管理', style: TextStyle(
            color: t.text, fontSize: 19, fontWeight: FontWeight.w600))),
          IconButton(tooltip: '导入订阅', icon: Icon(Icons.add, color: t.accent),
            onPressed: _addSubscription),
        ]),
        const SizedBox(height: 8),
        if (state.profiles.isEmpty) _subtitle('尚未导入订阅'),
        for (final profile in state.profiles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(state.currentProfileId == profile.id
              ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: t.accent),
            title: Text(profile.realLabel, style: TextStyle(color: t.text)),
            subtitle: _subtitle(profile.url.isEmpty ? '本地配置' : '远程订阅'),
            onTap: () => ref.read(currentProfileIdProvider.notifier).value = profile.id,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: '更新订阅', icon: const Icon(Icons.refresh),
                onPressed: profile.url.isEmpty ? null : () => ref.read(
                  profilesActionProvider.notifier).updateProfile(profile, showLoading: true)),
              IconButton(tooltip: '删除订阅', icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteSubscription(profile.id)),
            ]),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          FilledButton.icon(
            onPressed: _addSubscription,
            icon: const Icon(Icons.add_link),
            label: const Text('添加订阅 URL'),
          ),
          OutlinedButton.icon(
            onPressed: () => ref.read(profilesActionProvider.notifier).addProfileFormFile(),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('导入配置文件'),
          ),
        ]),
      ])),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vela 配色', style: TextStyle(color: t.text,
          fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (final palette in VelaPalette.all)
          RadioListTile<String>(
            title: Text(palette.name, style: TextStyle(color: t.text)),
            value: palette.id,
            groupValue: paletteId,
            onChanged: (value) { if (value != null) setState(() => paletteId = value); },
            activeColor: t.accent,
          ),
      ])),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('关于 Vela-SHUO', style: TextStyle(color: t.text,
          fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _subtitle('Vela-SHUO · 一帆越洋，尽览四方。'),
      ])),
    ]);
  }

  Future<void> _addSubscription() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加订阅'),
        content: TextField(controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://...',
            labelText: '订阅 URL',
          )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('导入')),
        ],
      ),
    );
    controller.dispose();
    if (url == null || !url.startsWith('https://')) return;
    ref.read(profilesActionProvider.notifier).addProfileFormURL(url);
  }

  Future<void> _deleteSubscription(int id) async {
    final accepted = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除订阅？'),
        content: const Text('删除后无法恢复该订阅的本地数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('删除')),
        ],
      ));
    if (accepted == true) {
      ref.read(profilesActionProvider.notifier).deleteProfile(id);
    }
  }
}


/// Ported from Vela-SHUO's original interface: same sail silhouette and hull.
class VelaBrandLogo extends StatelessWidget {
  const VelaBrandLogo({super.key, this.size = 65});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * .75),
    painter: const _VelaSailLogoPainter(),
  );
}

class _VelaSailLogoPainter extends CustomPainter {
  const _VelaSailLogoPainter();
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
  bool shouldRepaint(_VelaSailLogoPainter oldDelegate) => false;
}
