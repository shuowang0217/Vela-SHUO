import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../android/vela_android_vpn.dart';
import '../core/vela_connection_coordinator.dart';
import '../home/demo_connection.dart';
import '../home/globe.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import '../smart/vela_smart_controller.dart';
import '../subscription/vela_subscription_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import '../traffic/vela_traffic_monitor.dart';
import '../theme/vela_palettes.dart';
import 'stellar_design.dart';

/// The approved "interstellar console" proxy page. No simulated network
/// values are presented as real: cards, route, health and traffic come from
/// the same FlClash-backed controllers as the proven Windows home screen.
class VelaStellarProxyPage extends StatefulWidget {
  const VelaStellarProxyPage({super.key, required this.demo,
    this.subscription, this.connection, this.androidVpn, this.smart,
    this.traffic, required this.openConfig});
  final VelaDemoController demo;
  final VelaSubscriptionController? subscription;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;
  final VelaSmartController? smart;
  final VelaTrafficMonitor? traffic;
  final VoidCallback openConfig;

  @override
  State<VelaStellarProxyPage> createState() => _StellarProxyState();
}

class _StellarProxyState extends State<VelaStellarProxyPage> {
  String _query = '';
  String _region = '全部';
  String _group = '全部节点';
  bool _favoritesOnly = false;

  static const _regions = ['全部', '日本', '香港', '新加坡', '美国', '台湾', '韩国', '欧洲', '其他'];

  String _nodeRegion(String name) {
    final s = name.toLowerCase();
    for (final entry in <(String, List<String>)>[
      ('日本', ['日本', '东京', '大阪', '🇯🇵', 'japan', 'tokyo', 'osaka', 'jp-']),
      ('香港', ['香港', '🇭🇰', 'hong kong', 'hk-']),
      ('新加坡', ['新加坡', '狮城', '🇸🇬', 'singapore', 'sg-']),
      ('美国', ['美国', '洛杉矶', '纽约', '🇺🇸', 'usa', 'united states', 'us-']),
      ('台湾', ['台湾', '台北', '🇹🇼', 'taiwan', 'tw-']),
      ('韩国', ['韩国', '首尔', '🇰🇷', 'korea', 'kr-']),
      ('欧洲', ['英国', '德国', '法国', '荷兰', '🇬🇧', '🇩🇪', '🇫🇷',
               'london', 'frankfurt', 'europe', 'uk-', 'de-']),
    ]) {
      if (entry.$2.any(s.contains)) return entry.$1;
    }
    return '其他';
  }

  String _flag(String region) => switch (region) {
    '日本' => '🇯🇵', '香港' => '🇭🇰', '新加坡' => '🇸🇬',
    '美国' => '🇺🇸', '台湾' => '🇹🇼', '韩国' => '🇰🇷',
    '欧洲' => '🌍', _ => '✦',
  };

  Future<void> _choose(int index) async {
    final sub = widget.subscription;
    if (sub == null) return;
    final vpn = widget.androidVpn;
    final conn = widget.connection;
    final result = vpn?.connected == true
        ? await vpn!.switchNode(sub, index)
        : conn?.connected == true
            ? await conn!.switchNode(index)
            : await sub.selectNode(index);
    if (!mounted) return;
    if (result) {
      widget.smart?.manualSelection();
    } else {
      final message = vpn?.error ?? conn?.error ??
          sub.error ?? 'FlClash 未确认节点选择';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listeners = <Listenable>[
      widget.demo,
      if (widget.subscription != null) widget.subscription!,
      if (widget.connection != null) widget.connection!,
      if (widget.androidVpn != null) widget.androidVpn!,
      if (widget.smart != null) widget.smart!,
      if (widget.traffic != null) widget.traffic!,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(listeners),
      builder: (context, _) => StellarAtmosphere(
        child: LayoutBuilder(builder: (context, bounds) {
          final narrow = bounds.maxWidth < 650;
          final t = VelaThemeRuntime.active;
          final sub = widget.subscription;
          final nodes = sub?.nodes ?? const <VelaSubscriptionNode>[];
          final online = widget.connection?.connected == true ||
              widget.androidVpn?.connected == true;
          final flclash = sub is VelaFlClashSubscriptionController
              ? sub : null;
          final nativeGroups = flclash?.backend.groups ?? const <String>[];
          final groupNames = ['全部节点',
            ...nativeGroups.where((name) => name != 'GLOBAL'
                && (flclash?.backend.groupMembers[name]?.isNotEmpty ?? false))
                .take(7),
          ];
          final group = groupNames.contains(_group) ? _group : '全部节点';
          final membership = group == '全部节点'
              ? null : flclash?.backend.groupMembers[group]?.toSet();
          final order = widget.smart?.sortedIndices;
          final indices = sub?.visibleNodeIndices(
              query: _query, favoritesOnly: _favoritesOnly,
              order: order) ?? <int>[];
          final filtered = [
            for (final index in indices)
              if ((_region == '全部' ||
                   _nodeRegion(nodes[index].name) == _region) &&
                  (membership == null ||
                   membership.contains(nodes[index].name)))
                index,
          ];
          final busy = sub?.loading == true ||
              widget.connection?.busy == true ||
              widget.androidVpn?.busy == true;
          return SingleChildScrollView(
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1210),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    narrow ? 16 : 26, 24, narrow ? 16 : 26, 26),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: StellarSectionHeading('全球加速',
                        online ? '连接更大的世界 · FlClash 实时代理已接通'
                            : '连接更大的世界 · 由 FlClash 驱动你的航线')),
                      if (!narrow) StellarLabel(
                        online ? '●  已连接' : '○  待命',
                        accent: online, size: 13),
                    ]),
                    const SizedBox(height: 16),
                    _hero(context, online, nodes.length, narrow),
                    const SizedBox(height: 16),
                    if (nodes.isNotEmpty) ...[
                      _groupNavigation(context, groupNames, group, narrow),
                      const SizedBox(height: 16),
                      _activeRoute(context, online),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: Text('节点星图',
                            style: TextStyle(color: t.text,
                                fontWeight: FontWeight.bold, fontSize: 18))),
                        StellarLabel('共 ${nodes.length} 条线路 · 筛选结果 ${filtered.length}'),
                      ]),
                      const SizedBox(height: 11),
                      TextField(
                        key: const ValueKey('stellar_proxy_search'),
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.travel_explore_outlined),
                          hintText: '搜索节点名称、地区或协议',
                          filled: true,
                          fillColor: t.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15)),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: _favoritesOnly ? '显示全部节点' : '仅显示收藏',
                            onPressed: () => setState(
                                () => _favoritesOnly = !_favoritesOnly),
                            icon: Icon(_favoritesOnly
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                                color: _favoritesOnly ? t.accent : t.muted),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      SizedBox(height: 42, child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final region in _regions)
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                label: Text(region),
                                selected: _region == region,
                                onSelected: (_) =>
                                    setState(() => _region = region),
                              ),
                            ),
                        ],
                      )),
                      const SizedBox(height: 13),
                      if (filtered.isEmpty)
                        StellarPanel(child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Center(child: Text('当前筛选下没有节点',
                              style: TextStyle(color: t.muted))),
                        ))
                      else LayoutBuilder(builder: (context, grid) {
                        final count = grid.maxWidth > 850 ? 3
                            : grid.maxWidth > 470 ? 2 : 1;
                        final gap = 11.0;
                        final cellWidth = (grid.maxWidth -
                            gap * (count - 1)) / count;
                        return Wrap(spacing: gap, runSpacing: gap,
                          children: [
                            for (final index in filtered)
                              SizedBox(width: cellWidth,
                                child: _nodeCard(context, index, busy)),
                          ],
                        );
                      }),
                      const SizedBox(height: 17),
                      _testBar(context, narrow),
                    ] else _emptyState(context),
                  ],
                ),
              ),
            )),
          );
        }),
      ),
    );
  }

  Widget _hero(BuildContext context, bool online, int count, bool narrow) {
    final t = VelaThemeRuntime.active;
    final selected = widget.subscription?.selected;
    final latency = selected == null ? null
        : widget.smart?.resultAt(widget.subscription!.selectedIndex!)?.lastMs;
    final height = narrow ? 245.0 : 285.0;
    return StellarPanel(
      padding: EdgeInsets.zero,
      radius: 23,
      child: SizedBox(height: height, child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(children: [
          Positioned.fill(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              colors: [t.surface.withValues(alpha: .46),
                t.surface.withValues(alpha: .23),
                t.surface.withValues(alpha: .04)],
              stops: const [0, .40, 1],
            )),
          )),
          Positioned(left: 20, top: 19, right: narrow ? 64 : 275,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  StellarPlanetGlyph(size: 43),
                  const SizedBox(width: 10),
                  Expanded(child: Text(online ? '地球已接通' : '等待启航',
                    style: TextStyle(color: t.text, fontSize: narrow ? 18 : 22,
                      fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 8),
                Text(selected?.name ?? '你的下一条航线，从这里开始',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.accent, fontSize: 15)),
                const SizedBox(height: 12),
                StellarLabel('真实节点  $count    ·    FlClash / Mihomo'),
                const SizedBox(height: 6),
                StellarLabel(latency == null
                    ? '最近延迟  尚未测速'
                    : '最近延迟  $latency ms'),
                const SizedBox(height: 13),
                if (!narrow)
                  Text('一帆越洋，尽览四方。',
                      style: TextStyle(color: t.muted, letterSpacing: 2)),
              ],
            ),
          ),
          Positioned(left: 17, right: 17, bottom: 15,
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? Colors.greenAccent : t.muted)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                online ? '当前网络正在通过 FlClash 连接'
                    : '请选择节点，并在首页启动真实连接',
                style: TextStyle(color: t.text, fontSize: 12))),
              if (online && widget.traffic != null)
                StellarLabel('↓ ${VelaTrafficMonitor.rateMbps(
                    widget.traffic!.downloadBytesPerSecond)} Mbps'),
            ]),
          ),
        ]),
      )),
    );
  }

  Widget _groupNavigation(BuildContext context,
      List<String> groups, String selected, bool narrow) {
    final t = VelaThemeRuntime.active;
    return StellarPanel(padding: const EdgeInsets.all(11), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.hub_outlined, color: t.accent, size: 19),
          const SizedBox(width: 8),
          Text('代理星系', style: TextStyle(color: t.text,
              fontWeight: FontWeight.w600)),
          const Spacer(),
          StellarLabel('按 FlClash 原生代理组浏览'),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 7, children: [
          for (final group in groups)
            ChoiceChip(
              key: ValueKey('stellar_group_$group'),
              label: Text(group),
              selected: selected == group,
              onSelected: (_) => setState(() => _group = group),
            ),
        ]),
        const SizedBox(height: 5),
        StellarLabel('分组仅筛选列表；实际连接由 FlClash GLOBAL 节点选择控制。',
          size: 11),
      ],
    ));
  }

  Widget _activeRoute(BuildContext context, bool online) {
    final t = VelaThemeRuntime.active;
    final sub = widget.subscription;
    final selected = sub?.selected;
    final delay = sub?.selectedIndex == null ? null
        : widget.smart?.resultAt(sub!.selectedIndex!)?.lastMs;
    return StellarPanel(child: Row(children: [
      StellarPlanetGlyph(size: 48),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected?.name ?? '未选择节点',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          StellarLabel(online ? '●  实时连接中' : '○  节点待命',
            accent: online),
        ],
      )),
      if (delay != null) ...[
        Text('$delay ms', style: TextStyle(
          color: t.accent, fontWeight: FontWeight.w600)),
        const SizedBox(width: 13),
      ],
      if (widget.traffic != null && online)
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          StellarLabel('↑ ${VelaTrafficMonitor.rateMbps(
              widget.traffic!.uploadBytesPerSecond)} Mbps'),
          StellarLabel('↓ ${VelaTrafficMonitor.rateMbps(
              widget.traffic!.downloadBytesPerSecond)} Mbps'),
        ]),
    ]));
  }

  Widget _nodeCard(BuildContext context, int index, bool busy) {
    final sub = widget.subscription!;
    final t = VelaThemeRuntime.active;
    final node = sub.nodes[index];
    final picked = sub.selectedIndex == index;
    final health = widget.smart?.resultAt(index);
    final download = widget.smart?.downloadAt(index);
    final delay = health?.lastMs;
    final latencyError = sub is VelaFlClashSubscriptionController
        ? sub.backend.delayFailureFor(node.name) : null;
    final region = _nodeRegion(node.name);
    return StellarPanel(
      padding: EdgeInsets.zero, selected: picked, radius: 15,
      child: Material(color: Colors.transparent, child: InkWell(
        key: ValueKey('stellar_node_$index'),
        borderRadius: BorderRadius.circular(15),
        onTap: busy ? null : () => _choose(index),
        child: Padding(padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(_flag(region), style: const TextStyle(fontSize: 19)),
                const SizedBox(width: 7),
                Expanded(child: Text(node.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.text,
                    fontWeight: picked ? FontWeight.bold : FontWeight.w500))),
                SizedBox(width: 33, height: 33, child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: sub.isFavorite(index) ? '取消收藏' : '收藏节点',
                  onPressed: () => sub.toggleFavorite(index),
                  icon: Icon(sub.isFavorite(index)
                      ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 19, color: sub.isFavorite(index)
                          ? t.accent : t.muted),
                )),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Row(children: [
                  Flexible(child: StellarLabel(node.protocol.toUpperCase())),
                  if (picked) ...[
                    const SizedBox(width: 7),
                    Icon(Icons.check_circle, color: t.accent, size: 16),
                  ],
                ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: health?.samples == null
                          ? '尚未进行延迟测速'
                          : health!.reachable
                              ? 'FlClash 原生延迟测试'
                              : (latencyError ?? '节点延迟测试失败'),
                      child: Text(
                        health?.samples == null ? '延迟 —'
                            : health!.reachable ? '延迟 $delay ms'
                            : '延迟超时',
                        style: TextStyle(fontSize: 12,
                          color: health?.samples == null ? t.muted
                              : health!.reachable
                                  ? (delay! < 250
                                      ? const Color(0xFF38C9A4)
                                      : const Color(0xFFE6A54C))
                                  : const Color(0xFFD47575)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      download == null ? '下载 —'
                          : download.ok &&
                                  download.megabytesPerSecond != null
                              ? '下载 ${download.megabytesPerSecond!.toStringAsFixed(2)} MB/s'
                              : download.failureLabel,
                      style: TextStyle(fontSize: 12,
                        color: download == null ? t.muted
                            : download.ok
                                ? const Color(0xFF38C9A4)
                                : const Color(0xFFD47575)),
                    ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      )),
    );
  }

  /// One action measures both metrics for every imported node. The Smart
  /// page's AI country filter does not affect the Proxy page benchmark.
  Future<void> _runAllMeasurements() async {
    final smart = widget.smart;
    if (smart == null || !smart.canTestAll) return;
    if (smart.count > 50) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('确认全节点测速'),
          content: Text('将为全部 ${smart.count} 个节点分别检测延迟和下载速度。'
              '每节点通常下载约 1 MiB，部分失败线路可能尝试多个下载地址，'
              '实际流量可能更高。继续吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('开始测速')),
          ],
        ),
      );
      if (!mounted || accepted != true || !smart.canTestAll) return;
    }
    await smart.testAllNodes(includeAllCountries: true);
  }

  Widget _testBar(BuildContext context, bool narrow) {
    final smart = widget.smart;
    final t = VelaThemeRuntime.active;
    final running = smart?.scanning == true;
    final progress = smart == null || smart.total == 0
        ? 0.0 : (smart.scanned / math.max(1, smart.total)).clamp(0.0, 1.0);
    final action = FilledButton.icon(
      key: const ValueKey('stellar_full_benchmark'),
      onPressed: running ? smart!.cancelScan
          : smart?.canTestAll == true ? _runAllMeasurements : null,
      icon: Icon(running ? Icons.stop_rounded : Icons.speed_rounded, size: 18),
      label: Text(running ? '停止测速' : '全节点测速 · 延迟 + 下载'),
    );
    return StellarPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.bolt_rounded, color: t.accent),
          const SizedBox(width: 7),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('星图全节点测速',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              StellarLabel(smart == null ? '当前平台尚未接入批量测速'
                  : running ? '正在为所有节点测试延迟和下载速度…'
                  : smart.status?.isNotEmpty == true
                      ? smart.status!
                      : '同时测量每条线路的延迟与真实下载速度'),
            ],
          )),
          if (!narrow) ...[
            const SizedBox(width: 12),
            action,
          ],
        ]),
        if (narrow) ...[
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: action),
        ],
        if (running || (smart?.total ?? 0) > 0) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress, minHeight: 5,
              borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 7),
          StellarLabel('已测 ${smart!.scanned}/${smart.total}'
              ' · 延迟成功 ${smart.successful}'
              ' · 下载成功 ${smart.downloadsSuccessful}'
              '/${smart.downloadsTested}'),
        ],
      ],
    ));
  }

  Widget _emptyState(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return StellarPanel(child: Column(children: [
      const SizedBox(height: 16),
      StellarPlanetGlyph(size: 74),
      const SizedBox(height: 12),
      Text('星图尚未载入', style: TextStyle(color: t.text,
        fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      StellarLabel('导入 FlClash 订阅后，真实节点将在这里点亮'),
      const SizedBox(height: 14),
      StellarAction(
        key: const ValueKey('stellar_open_config'),
        label: '前往配置管理', icon: Icons.add_rounded,
        filled: true, onPressed: widget.openConfig),
      const SizedBox(height: 12),
    ]));
  }
}
