import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/vela_shuo/theme/vela_palettes.dart';
import 'vela_original_home.dart';

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
  final TextEditingController _nodeSearch = TextEditingController();
  bool favoritesOnly = false;
  final Set<String> favoriteNames = <String>{};
  String paletteId = VelaPalette.defaultId;

  @override
  void dispose() {
    _nodeSearch.dispose();
    super.dispose();
  }

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
    final palette = VelaPalette.byId(paletteId);
    // Original Vela defaults to the dark Ocean theme. Do not inherit the
    // upstream FlClash MaterialApp brightness (which may be light).
    final brightness = palette.prefersDark ? Brightness.dark : Brightness.light;
    VelaThemeRuntime.select(palette, brightness);
    final t = VelaThemeRuntime.active;
    final desktop = Platform.isWindows || MediaQuery.sizeOf(context).width >= 820;
    final extended = MediaQuery.sizeOf(context).width >= 1250;
    final pages = [_home(), _nodes(), _smart(), _settings()];
    return Theme(
      data: Theme.of(context).copyWith(
        useMaterial3: true,
        brightness: brightness,
        scaffoldBackgroundColor: t.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: brightness,
          surface: t.background,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
    // Exactly match the original Vela centered, padded screen framing.
    final subtitle = switch (title) {
      '节点' => '来自真实订阅的节点 · 点击选择后返回首页',
      '智能优选' => '稳定优先 · 让每一次连接更从容',
      '设置' => '为 Vela-SHUO 定义你的使用方式',
      _ => '',
    };
    return VelaScreenPadding(child: ListView(children: [
      VelaScreenHeading(title, subtitle),
      const SizedBox(height: 18),
      ...children,
    ]));
  }

  Widget _card(Widget content) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: VelaGlassCard(child: content),
  );

  Widget _subtitle(String text) => Text(text, style:
    TextStyle(fontSize: 13, color: VelaThemeRuntime.active.muted));

  // This is the original Vela home composition, not a new dashboard card.
  Widget _home() => VelaOriginalHome(
    // Pass the full-window layout decision into the original Vela canvas.
    desktop: Platform.isWindows || MediaQuery.sizeOf(context).width >= 820,
    showNodes: () => setState(() => tab = 1),
    showSmart: () => setState(() => tab = 2),
  );

  Widget _nodes() {
    final t = VelaThemeRuntime.active;
    final groups = ref.watch(visibleGroupsStateProvider).value;
    final selected = ref.watch(currentProfileProvider)?.selectedMap
      ?? <String, String>{};
    final allNodes = groups.expand((g) => g.all.map((p) =>
      (group: g, proxy: p))).toList();
    final matching = allNodes.where((e) {
      final key = e.group.name + '|' + e.proxy.name;
      final hit = e.proxy.name.toLowerCase().contains(query.trim().toLowerCase());
      return hit && (!favoritesOnly || favoriteNames.contains(key));
    }).toList();
    return _page('节点', [
      TextField(
        key: const ValueKey('node_search_input'),
        controller: _nodeSearch,
        maxLength: 80,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => query = value),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索节点名称或协议',
          prefixIcon: const Icon(Icons.search_rounded),
          border: const OutlineInputBorder(),
          counterText: '',
          suffixIcon: query.isEmpty ? null : IconButton(
            key: const ValueKey('node_search_clear'),
            tooltip: '清除搜索',
            onPressed: () { _nodeSearch.clear(); setState(() => query = ''); },
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ),
      const SizedBox(height: 9),
      Wrap(
        spacing: 12,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            key: const ValueKey('node_favorites_only'),
            label: Text('仅收藏 (' + favoriteNames.length.toString() + ')'),
            selected: favoritesOnly,
            onSelected: (checked) => setState(() => favoritesOnly = checked),
            avatar: const Icon(Icons.star_rounded, size: 17),
          ),
          Text('显示 ' + matching.length.toString() + ' / ' +
            allNodes.length.toString() + ' 个节点',
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      const SizedBox(height: 12),
      if (allNodes.isEmpty)
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('尚未导入订阅', style: TextStyle(color: t.text)),
            const SizedBox(height: 10),
            _subtitle('请在「设置」添加订阅。'),
            TextButton(onPressed: () => setState(() => tab = 3),
              child: const Text('前往订阅管理')),
          ]))
      else if (matching.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('没有匹配的节点，可清除搜索或关闭「仅收藏」'),
        ),
      for (final group in groups)
        if (matching.any((entry) => entry.group.name == group.name)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 12),
            child: Text(group.name, style: TextStyle(
              color: t.text, fontSize: 18, fontWeight: FontWeight.w600))),
          for (final entry in matching.where((e) =>
            e.group.name == group.name))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: VelaGlassCard(
                padding: EdgeInsets.zero,
                child: Consumer(builder: (context, ref, _) {
                  final proxy = entry.proxy;
                  final key = group.name + '|' + proxy.name;
                  final favorite = favoriteNames.contains(key);
                  final delay = ref.watch(delayProvider(proxyName: proxy.name));
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: IconButton(
                      key: ValueKey('node_favorite_' + key),
                      tooltip: favorite ? '取消收藏' : '收藏节点',
                      onPressed: () => setState(() {
                        if (favorite) { favoriteNames.remove(key); }
                        else { favoriteNames.add(key); }
                      }),
                      icon: Icon(favorite ? Icons.star_rounded
                        : Icons.star_border_rounded,
                        color: favorite ? t.accentSoft : t.muted),
                    ),
                    title: Text(proxy.name, style: TextStyle(color: t.text)),
                    subtitle: Text(delay == null ? '未测速'
                      : delay.toString() + ' ms',
                      style: TextStyle(color: t.muted)),
                    trailing: selected[group.name] == proxy.name
                      ? Icon(Icons.check_circle, color: t.accentSoft)
                      : Icon(Icons.chevron_right, color: t.accent),
                    onTap: () async {
                      await ref.read(proxiesActionProvider.notifier).changeProxy(
                        groupName: group.name, proxyName: proxy.name);
                      if (mounted) setState(() => tab = 0);
                    },
                  );
                }),
              ),
            ),
        ],
      const SizedBox(height: 16),
      _subtitle('节点延迟来自 FlClash 内核真实探测；收藏暂仅在本次运行有效。'),
    ]);
  }

  Widget _smart() {
    final t = VelaThemeRuntime.active;
    final groups = ref.watch(visibleGroupsStateProvider).value;
    final running = ref.watch(isStartProvider);
    final profile = ref.watch(currentProfileProvider);
    final names = profile?.selectedMap.values;
    final selected = names != null && names.isNotEmpty ? names.first : '未选择';
    final nodes = groups.expand((g) => g.all).toList();
    return _page('智能优选', [
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SHUO Smart · 节点优选', style: TextStyle(
          color: t.text, fontWeight: FontWeight.w600, fontSize: 17)),
        const SizedBox(height: 8),
        Text('当前节点：' + selected + '  ·  下载速度：—',
          style: TextStyle(color: t.muted, fontSize: 12)),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          key: const ValueKey('smart_auto_pick'),
          contentPadding: EdgeInsets.zero,
          value: false,
          title: Text('启用智能优选', style: TextStyle(color: t.text)),
          subtitle: Text('自动测速和切换尚未适配到底层服务',
            style: TextStyle(color: t.muted, fontSize: 11)),
          onChanged: null,
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('smart_ai_mode'),
          contentPadding: EdgeInsets.zero,
          value: false,
          title: Text('AI 模式 · 单国家优选',
            style: TextStyle(color: t.text)),
          subtitle: Text('国家优选尚未完成适配',
            style: TextStyle(color: t.muted, fontSize: 11)),
          onChanged: null,
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          key: const ValueKey('smart_measure_all'),
          onPressed: !running || groups.isEmpty ? null
            : () => ref.read(proxiesActionProvider.notifier).delayTestGroups(groups),
          icon: const Icon(Icons.speed_rounded, size: 19),
          label: const Text('一键测速 · 全节点延迟'),
        )),
        const SizedBox(height: 12),
        Text('本版调用内核真实延迟探测；未实现下载测速与自动选线。',
          style: TextStyle(color: t.muted, fontSize: 12)),
        const SizedBox(height: 14),
        Divider(color: t.line),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('节点排行榜', style: TextStyle(
            color: t.text, fontWeight: FontWeight.w600))),
          Text('延迟 ms', style: TextStyle(color: t.muted, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        for (final proxy in nodes.take(40))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Consumer(builder: (context, ref, _) {
              final delay = ref.watch(delayProvider(proxyName: proxy.name));
              return Row(children: [
                Expanded(child: Text(proxy.name, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.text, fontSize: 12))),
                const SizedBox(width: 8),
                Text(delay == null ? '未测试' : delay.toString() + ' ms',
                  style: TextStyle(color: delay == null ? t.muted : t.accent,
                    fontSize: 11)),
              ]);
            }),
          ),
        if (nodes.length > 40)
          Text('首批展示 40 个节点；完整节点列表请到「节点」页面。',
            style: TextStyle(color: t.muted, fontSize: 11)),
      ])),
    ]);
  }

  Widget _settings() {
    final t = VelaThemeRuntime.active;
    final state = ref.watch(profilesStateProvider);
    final proxy = ref.watch(networkSettingProvider);
    final vpn = ref.watch(vpnSettingProvider);
    final mode = ref.watch(patchClashConfigProvider).mode;
    return _page('设置', [
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('连接与代理', style: TextStyle(color: t.text,
          fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _subtitle('工作模式'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final item in const [
            (Mode.rule, '规则'),
            (Mode.global, '全局'),
            (Mode.direct, '直连'),
          ])
            ChoiceChip(
              label: Text(item.$2),
              selected: mode == item.$1,
              onSelected: (enabled) {
                if (!enabled) return;
                final config = ref.read(patchClashConfigProvider);
                ref.read(patchClashConfigProvider.notifier).value =
                  config.copyWith(mode: item.$1);
              },
            ),
        ]),
        if (Platform.isWindows) SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('系统代理'),
          subtitle: _subtitle('开启连接时由后台服务管理系统代理'),
          value: proxy.systemProxy,
          onChanged: (enabled) {
            ref.read(networkSettingProvider.notifier).value =
              proxy.copyWith(systemProxy: enabled);
          },
        ),
        if (Platform.isAndroid) SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('VPN 服务'),
          subtitle: _subtitle('通过 Android 系统授权开启 VPN'),
          value: vpn.enable,
          onChanged: (enabled) {
            ref.read(vpnSettingProvider.notifier).value =
              vpn.copyWith(enable: enabled);
          },
        ),
      ])),
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
      VelaPaletteGrid(
        paletteId: paletteId,
        onSelected: (id) => setState(() => paletteId = id),
      ),
      const SizedBox(height: 16),
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
