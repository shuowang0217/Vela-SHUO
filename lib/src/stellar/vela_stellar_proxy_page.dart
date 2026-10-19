import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../brand/vela_glass_toast.dart';

import '../android/vela_android_vpn.dart';
import '../core/vela_connection_coordinator.dart';
import '../home/demo_connection.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import '../network/vela_routing_mode.dart';
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
    this.traffic, this.routing, required this.openConfig});
  final VelaDemoController demo;
  final VelaSubscriptionController? subscription;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;
  final VelaSmartController? smart;
  final VelaTrafficMonitor? traffic;
  final VelaRoutingModeController? routing;
  final VoidCallback openConfig;

  @override
  State<VelaStellarProxyPage> createState() => _StellarProxyState();
}

class _StellarProxyState extends State<VelaStellarProxyPage> {
  String _query = '';
  String _region = '全部';
  String? _group;
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
          sub.error ?? '航线服务未确认节点选择';
      VelaGlassToast.show(context, message);
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
      if (widget.routing != null) widget.routing!,
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
          // FlClash RULE hides GLOBAL/hidden, GLOBAL shows native groups,
          // DIRECT displays none. Never inject synthetic group tabs.
          final groupNames = flclash?.backend.visibleGroups ?? const <String>[];
          final group = groupNames.contains(_group)
              ? _group : groupNames.firstOrNull;
          final membership = group == null
              ? const <String>{}
              : flclash?.backend.groupMembers[group]?.toSet() ??
                  const <String>{};
          final nestedGroups = flclash == null || group == null
              ? const <String>[]
              : [
                  for (final member in flclash.backend.groupMembers[group] ??
                      const <String>[])
                    if (flclash.backend.groups.contains(member)) member,
                ];
          final order = widget.smart?.sortedIndices;
          final indices = sub?.visibleNodeIndices(
              query: _query, favoritesOnly: _favoritesOnly,
              order: order) ?? <int>[];
          final filtered = [
            for (final index in indices)
              if ((_region == '全部' ||
                   _nodeRegion(nodes[index].name) == _region) &&
                  (flclash == null ||
                   (group != null && membership.contains(nodes[index].name))))
                index,
          ];
          final busy = sub?.loading == true ||
              widget.connection?.busy == true ||
              widget.androidVpn?.busy == true;
          return SingleChildScrollView(
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 885),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    narrow ? 16 : 25, narrow ? 78 : 77,
                    narrow ? 16 : 25, narrow ? 110 : 105),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: StellarSectionHeading('全球加速',
                        online ? '连接更大的世界 · 航线已接通'
                            : '连接更大的世界 · 选择适合你的航线')),
                      if (!narrow) StellarLabel(
                        online ? '●  已连接' : '○  待命',
                        accent: online, size: 13),
                    ]),
                    const SizedBox(height: 16),
                    _hero(context, online, nodes.length, narrow),
                    const SizedBox(height: 16),
                    if (nodes.isNotEmpty) ...[
                      if (groupNames.isNotEmpty)
                        _groupNavigation(context, groupNames, group, narrow)
                      else if (flclash != null)
                        StellarPanel(child: StellarLabel(
                          '直连模式：当前模式不显示代理策略组，流量走 DIRECT')),
                      const SizedBox(height: 16),
                      if (nestedGroups.isNotEmpty) ...[
                        _nestedGroupChoices(context, nestedGroups, group),
                        const SizedBox(height: 12),
                      ],
                      _activeRoute(context, online),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: Text('航线节点',
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
                        // Two compact columns on phones, three on large desktops.
                        final count = grid.maxWidth > 850 ? 3 : 2;
                        final gap = 11.0;
                        final cellWidth = (grid.maxWidth -
                            gap * (count - 1)) / count;
                        return Wrap(spacing: gap, runSpacing: gap,
                          children: [
                            for (final index in filtered)
                              SizedBox(width: cellWidth,
                                child: _nodeCard(context, index, busy,
                                    compact: cellWidth < 230)),
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
    final height = narrow ? 198.0 : 192.0;
    return StellarPanel(
      padding: EdgeInsets.zero,
      radius: 23,
      child: SizedBox(height: height, child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(children: [
          Positioned.fill(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              colors: [t.surface.withValues(alpha: .25),
                t.surface.withValues(alpha: .10),
                t.surface.withValues(alpha: .015)],
              stops: const [0, .40, 1],
            )),
          )),
          Positioned(left: 20, top: 16, right: 20,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  StellarCompassGlyph(size: 43),
                  const SizedBox(width: 10),
                  Expanded(child: Text('当前航线 · ${widget.subscription is VelaFlClashSubscriptionController ? ((widget.subscription! as VelaFlClashSubscriptionController).profileName ?? '未命名机场') : '未命名机场'}',
                    style: TextStyle(color: t.text, fontSize: narrow ? 18 : 22,
                      fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 8),
                Text(selected?.name ?? '你的下一条航线，从这里开始',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.accent, fontSize: 15)),
                const SizedBox(height: 12),
                StellarLabel('真实节点  $count    ·    航线服务'),
                const SizedBox(height: 6),
                StellarLabel(latency == null
                    ? '最近延迟  尚未测速'
                    : '最近延迟  $latency ms'),
                const SizedBox(height: 13),

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
                online ? '当前网络正沿选定航线连接'
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

  void _selectGroup(String label) {
    final sub = widget.subscription;
    if (sub is VelaFlClashSubscriptionController &&
        !sub.selectRoutingGroup(label)) {
      VelaGlassToast.show(context, '代理核心未找到当前策略组');
      return;
    }
    // Group navigation never changes Mihomo route mode or selected outbound.
    setState(() => _group = label);
  }

  Future<void> _chooseNestedGroup(String name) async {
    final sub = widget.subscription;
    if (sub is! VelaFlClashSubscriptionController) return;
    final ok = await sub.selectGroupMember(name);
    if (!mounted) return;
    if (!ok) {
      VelaGlassToast.show(context, sub.error ?? '下级策略组未被核心确认');
    }
  }

  Widget _nestedGroupChoices(BuildContext context,
      List<String> entries, String? group) {
    final backend = (widget.subscription as VelaFlClashSubscriptionController)
        .backend;
    return StellarPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        StellarLabel('当前策略组可选的下级策略组'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 7, children: [
          for (final item in entries)
            ChoiceChip(
              key: ValueKey('stellar_nested_group_$item'),
              label: Text(item),
              selected: backend.groupNow[group] == item,
              onSelected: backend.groupIsSelector(group ?? '')
                  ? (_) => _chooseNestedGroup(item) : null,
            ),
        ]),
      ],
    ));
  }

  Widget _groupNavigation(BuildContext context,
      List<String> groups, String? selected, bool narrow) {
    final t = VelaThemeRuntime.active;
    return StellarPanel(padding: const EdgeInsets.all(11), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.hub_outlined, color: t.accent, size: 19),
          const SizedBox(width: 8),
          Text('航线分组', style: TextStyle(color: t.text,
              fontWeight: FontWeight.w600)),
          const Spacer(),
          StellarLabel(
              '当前出口组：${widget.subscription is VelaFlClashSubscriptionController ? (widget.subscription! as VelaFlClashSubscriptionController).backend.activeGroup ?? "未选中" : "未选中"}'),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 7, children: [
          for (final group in groups)
            ChoiceChip(
              key: ValueKey('stellar_group_$group'),
              label: Text(group),
              selected: selected == group,
              onSelected: (_) => _selectGroup(group),
            ),
        ]),
        const SizedBox(height: 5),
        StellarLabel('分组与规则来自 代理核心；切换标签不会改变线路。',
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
      StellarCompassGlyph(size: 48),
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

  Widget _nodeCard(BuildContext context, int index, bool busy,
      {bool compact = false}) {
    final sub = widget.subscription!;
    final t = VelaThemeRuntime.active;
    final node = sub.nodes[index];
    final picked = sub.selectedIndex == index;
    final health = widget.smart?.resultAt(index);
    final download = widget.smart?.downloadAt(index);
    final delay = health?.lastMs;
    final latencyError = sub is VelaFlClashSubscriptionController
        ? sub.backend.delayFailureFor(node.name) : null;
    final delayText = health?.samples == null ? '延迟 —'
        : health!.reachable ? '延迟 $delay ms' : '延迟超时';
    final downloadText = download == null ? '下载 —'
        : download.ok && download.megabytesPerSecond != null
            ? '下载 ${download.megabytesPerSecond!.toStringAsFixed(2)} MB/s'
            : download.failureLabel;
    final latencyColor = health?.samples == null ? t.muted
        : health!.reachable
            ? ((delay ?? 0) < 250
                ? const Color(0xFF38C9A4) : const Color(0xFFE6A54C))
            : const Color(0xFFD47575);
    final downloadColor = download == null ? t.muted : download.ok
        ? const Color(0xFF38C9A4) : const Color(0xFFD47575);
    return StellarPanel(
      padding: EdgeInsets.zero, selected: picked, radius: 15,
      child: Material(color: Colors.transparent, child: InkWell(
        key: ValueKey('stellar_node_$index'),
        borderRadius: BorderRadius.circular(15),
        onTap: busy ? null : () => _choose(index),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(_flag(_nodeRegion(node.name)),
                    style: TextStyle(fontSize: compact ? 15 : 19)),
                SizedBox(width: compact ? 3 : 7),
                Expanded(child: Text(node.name, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.text, fontSize: compact ? 12 : 14,
                    fontWeight: picked ? FontWeight.bold : FontWeight.w500))),
                SizedBox(width: compact ? 26 : 33,
                  height: compact ? 28 : 33,
                  child: IconButton(padding: EdgeInsets.zero,
                    tooltip: sub.isFavorite(index) ? '取消收藏' : '收藏节点',
                    onPressed: () => sub.toggleFavorite(index),
                    icon: Icon(sub.isFavorite(index)
                        ? Icons.star_rounded : Icons.star_border_rounded,
                        size: compact ? 17 : 19,
                        color: sub.isFavorite(index) ? t.accent : t.muted))),
              ]),
              SizedBox(height: compact ? 5 : 12),
              Row(children: [
                Expanded(child: Text(node.protocol.toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.muted, fontSize: 11))),
                if (picked) Icon(Icons.check_circle, color: t.accent,
                    size: compact ? 14 : 16),
              ]),
              SizedBox(height: compact ? 5 : 7),
              Tooltip(message: health?.samples == null ? '尚未进行延迟测速'
                  : health!.reachable ? '真实节点延迟测试'
                  : (latencyError ?? '节点延迟测试失败'),
                child: Text(delayText, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: compact ? 11 : 12,
                    color: latencyColor))),
              const SizedBox(height: 3),
              Text(downloadText, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 11 : 12,
                  color: downloadColor)),
            ],
          ),
        ),
      )),
    );
  }

  Future<void> _runDownloadMeasurements() async {
    final smart = widget.smart;
    if (smart == null || !smart.canTestAll) return;
    if (smart.count > 30) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('确认全节点下载测速'),
          content: Text('即将对 ${smart.count} 条线路逐个下载真实 HTTPS 样本。'
              '每个节点约 1 MiB，失败时可能消耗更多流量；'
              '延迟结果不会重测或清除。继续吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('开始下载测速')),
          ],
        ),
      );
      if (!mounted || accepted != true || !smart.canTestAll) return;
    }
    await smart.testAllDownloads();
  }

  Widget _testBar(BuildContext context, bool narrow) {
    final smart = widget.smart;
    final t = VelaThemeRuntime.active;
    final running = smart?.scanning == true;
    final isDownload = smart?.scanKind == 'download';
    final progress = smart == null || smart.total == 0
        ? 0.0 : (smart.scanned / math.max(1, smart.total)).clamp(0.0, 1.0);
    final latencyButton = FilledButton.icon(
      key: const ValueKey('stellar_latency_benchmark'),
      onPressed: running ? (isDownload ? null : smart!.cancelScan)
          : smart?.canTestAll == true ? smart!.testAllLatencies : null,
      icon: Icon(running && !isDownload ? Icons.stop_rounded
          : Icons.network_check_rounded, size: 17),
      label: Text(running && !isDownload ? '停止测速' : '延迟测速'),
    );
    final downloadButton = OutlinedButton.icon(
      key: const ValueKey('stellar_download_benchmark'),
      onPressed: running ? (isDownload ? smart!.cancelScan : null)
          : smart?.canTestAll == true ? _runDownloadMeasurements : null,
      icon: Icon(running && isDownload ? Icons.stop_rounded
          : Icons.download_rounded, size: 17),
      label: Text(running && isDownload ? '停止下载' : '下载测速'),
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
              Text('航线节点测速',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              StellarLabel(smart == null ? '当前平台尚未接入批量测速'
                  : running ? (smart.status ?? '正在测试…')
                  : smart.status?.isNotEmpty == true ? smart.status!
                  : '先快速测延迟；需要真实吞吐量时单独测下载'),
            ],
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: latencyButton),
          const SizedBox(width: 10),
          Expanded(child: downloadButton),
        ]),
        if (running || (smart?.total ?? 0) > 0) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress, minHeight: 5,
            borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 7),
          StellarLabel('已测 ${smart!.scanned}/${smart.total}'
              ' · ${isDownload ? "下载" : "延迟"}成功 ${smart.successful}'
              ' · 失败 ${smart.failed}'),
        ],
      ],
    ));
  }

  Widget _emptyState(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return StellarPanel(child: Column(children: [
      const SizedBox(height: 16),
      StellarCompassGlyph(size: 74),
      const SizedBox(height: 12),
      Text('航线尚未载入', style: TextStyle(color: t.text,
        fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      StellarLabel('导入机场订阅后，真实航线节点将在这里显示'),
      const SizedBox(height: 14),
      StellarAction(
        key: const ValueKey('stellar_open_config'),
        label: '前往配置管理', icon: Icons.add_rounded,
        filled: true, onPressed: widget.openConfig),
      const SizedBox(height: 12),
    ]));
  }
}
