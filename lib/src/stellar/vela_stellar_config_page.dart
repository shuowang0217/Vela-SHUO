import 'package:flutter/material.dart';

import '../android/vela_android_vpn.dart';
import '../core/vela_connection_coordinator.dart';
import '../core/vela_core_controller.dart';
import '../home/demo_connection.dart';
import '../home/globe.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import 'vela_stellar_import_dialog.dart';
import '../subscription/vela_subscription_controller.dart';
import '../theme/vela_palettes.dart';
import 'stellar_design.dart';

/// Configuration management in the approved orbital-card visual language.
/// Current FlClash integration has one active on-device profile. This view
/// deliberately shows real data only; it does NOT fabricate other profiles,
/// provider quota, scheduled updates, or server-side expiration.
class VelaStellarConfigPage extends StatefulWidget {
  const VelaStellarConfigPage({super.key, required this.demo,
    required this.core, this.subscription, this.connection, this.androidVpn});
  final VelaDemoController demo;
  final VelaCoreController? core;
  final VelaSubscriptionController? subscription;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;

  @override
  State<VelaStellarConfigPage> createState() => _StellarConfigState();
}

class _StellarConfigState extends State<VelaStellarConfigPage> {
  bool _busy = false;
  bool _sortRecent = true;

  VelaFlClashSubscriptionController? get _native =>
      widget.subscription is VelaFlClashSubscriptionController
          ? widget.subscription as VelaFlClashSubscriptionController : null;

  Map<String, dynamic>? get _subscriptionUsage {
    // FlClash Profile.update() reads subscription-userinfo from the final
    // subscription HTTP response. Most paid subscriptions are a root profile,
    // NOT a Mihomo proxy-provider. Prefer that authoritative metadata.
    final nativeUsage = _native?.backend.subscriptionUsage;
    if (nativeUsage != null) {
      return {
        'upload': nativeUsage.upload,
        'download': nativeUsage.download,
        'total': nativeUsage.total,
        if (nativeUsage.expire != null) 'expire': nativeUsage.expire,
      };
    }
    final values = _native?.backend.providerSnapshots ?? const [];
    // Show a quota only when FlClash returned an authoritative upload,
    // download and total for an actual subscription provider.
    for (final provider in values) {
      final raw = provider['subscription-info'];
      if (raw is! Map) continue;
      final upload = raw['upload'];
      final download = raw['download'];
      final total = raw['total'];
      if (upload is num && download is num && total is num && total > 0 &&
          upload >= 0 && download >= 0) {
        return Map<String, dynamic>.from(raw);
      }
    }
    return null;
  }

  String _humanBytes(num bytes) {
    final n = bytes.toDouble();
    if (n >= 1024 * 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (n >= 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _elapsed(DateTime? instant) {
    if (instant == null) return '暂无记录';
    final elapsed = DateTime.now().difference(instant);
    if (elapsed.inMinutes < 1) return '刚刚';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inHours < 24) return '${elapsed.inHours} 小时前';
    return '${elapsed.inDays} 天前';
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    if (_busy || widget.connection?.connected == true ||
        widget.androidVpn?.active == true) {
      return;
    }
    final sub = widget.subscription;
    if (sub == null) return;
    setState(() => _busy = true);
    try {
      final native = _native;
      bool ok;
      if (sub.canRefresh) {
        ok = await sub.refreshLastUrl();
      } else if (native?.canRefreshProviders == true) {
        ok = await native!.refreshNativeProviders();
      } else {
        _notify('没有本次运行的订阅地址或可更新的 HTTP 提供者；可重新导入配置');
        return;
      }
      _notify(ok ? 'FlClash 配置更新成功'
          : sub.error ?? '更新失败，原节点列表保持不变');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openImporter() async {
    final controller = widget.subscription;
    final core = widget.core;
    if (controller == null || core == null) {
      _notify('FlClash 核心尚未就绪');
      return;
    }
    if (widget.connection?.connected == true ||
        widget.androidVpn?.active == true || core.isListening) {
      _notify('为保护当前连接，请先断开再切换配置');
      return;
    }
    final imported = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VelaStellarImportDialog(controller: controller),
    );
    if (!mounted) return;
    if (imported == true) {
      _notify('FlClash 已成功导入配置，${controller.nodes.length} 个节点');
    }
  }

  Future<void> _showManagement() async {
    final sub = widget.subscription;
    if (sub == null) return;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: VelaThemeRuntime.active.background,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StellarSectionHeading('配置操作', '仅执行已经接入 FlClash 的真实功能'),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('更新当前配置'),
              enabled: sub.canRefresh || _native?.canRefreshProviders == true,
              onTap: () { Navigator.pop(ctx); _refresh(); },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('加密保存本机'),
              subtitle: const Text('使用系统安全存储，不保存订阅 URL'),
              enabled: sub.canSave,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await sub.saveOnDevice();
                _notify(ok ? '已加密保存本机配置' : sub.error ?? '加密保存失败');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('导入或替换当前配置'),
              onTap: () { Navigator.pop(ctx); _openImporter(); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listeners = <Listenable>[
      widget.demo,
      if (widget.subscription != null) widget.subscription!,
      if (widget.connection != null) widget.connection!,
      if (widget.androidVpn != null) widget.androidVpn!,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(listeners),
      builder: (context, _) => StellarAtmosphere(
        child: LayoutBuilder(builder: (context, bounds) {
          final narrow = bounds.maxWidth < 660;
          final t = VelaThemeRuntime.active;
          final sub = widget.subscription;
          final hasProfile = sub?.nodes.isNotEmpty == true;
          final online = widget.connection?.connected == true ||
              widget.androidVpn?.connected == true;
          final updated = sub?.lastUpdatedAt;
          final usage = _subscriptionUsage;
          final total = usage?['total'] as num?;
          final uploaded = usage?['upload'] as num?;
          final downloaded = usage?['download'] as num?;
          final used = uploaded != null && downloaded != null
              ? uploaded + downloaded : null;
          final percent = total != null && total > 0 && used != null
              ? (used / total).clamp(0.0, 1.0).toDouble() : null;
          return SingleChildScrollView(
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1190),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 16 : 28, 22, narrow ? 16 : 28, 30),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: StellarSectionHeading(
                        '配置管理', '订阅世界的更多可能 · FlClash 原生配置')),
                      if (!narrow)
                        StellarAction(label: '刷新配置',
                          icon: Icons.sync_rounded,
                          onPressed: _busy || !hasProfile ||
                            online ? null : _refresh),
                    ]),
                    const SizedBox(height: 16),
                    _hero(context, narrow, hasProfile, online,
                      used, total, percent, updated),
                    const SizedBox(height: 18),
                    if (narrow)
                      Row(children: [
                        Expanded(child: StellarAction(
                          label: '刷新当前配置',
                          icon: Icons.refresh_rounded,
                          onPressed: _busy || !hasProfile || online
                              ? null : _refresh)),
                        const SizedBox(width: 10),
                        StellarAction(label: '管理', icon: Icons.more_horiz,
                            onPressed: _showManagement),
                      ]),
                    if (narrow) const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: Text('我的航线配置',
                        style: TextStyle(color: t.text,
                          fontWeight: FontWeight.bold, fontSize: 19))),
                      TextButton.icon(
                        onPressed: () => setState(() => _sortRecent = !_sortRecent),
                        icon: const Icon(Icons.sort_rounded, size: 17),
                        label: Text(_sortRecent ? '最近更新' : '默认顺序'),
                      ),
                      IconButton(
                        tooltip: '更多配置操作',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: _showManagement,
                      ),
                    ]),
                    const SizedBox(height: 10),
                    if (hasProfile)
                      _profileCard(context, selected: true,
                        used: used, total: total, percent: percent,
                        online: online)
                    else _emptyProfile(context),
                    const SizedBox(height: 15),
                    StellarPanel(child: Row(children: [
                      StellarPlanetGlyph(size: 46),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('开启下一段航线',
                            style: TextStyle(color: t.text,
                              fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 5),
                          const StellarLabel(
                              '导入新的订阅或 Mihomo 配置 · 本机安全管理'),
                        ],
                      )),
                      IconButton.filledTonal(
                        key: const ValueKey('stellar_add_profile'),
                        onPressed: _openImporter,
                        icon: const Icon(Icons.add_rounded),
                        tooltip: '添加配置',
                      ),
                    ])),
                    const SizedBox(height: 14),
                    StellarLabel('目前 FlClash 适配层支持单活动配置。'
                        '多配置切换需进一步接入 FlClash 的完整 Profile 管理，'
                        '不会显示虚构的其他订阅或套餐用量。'),
                  ],
                ),
              ),
            )),
          );
        }),
      ),
    );
  }

  Widget _hero(BuildContext context, bool narrow, bool active,
      bool online, num? used, num? total, double? percent,
      DateTime? updated) {
    final t = VelaThemeRuntime.active;
    return StellarPanel(padding: EdgeInsets.zero, radius: 24,
      child: SizedBox(height: narrow ? 246 : 285,
        child: ClipRRect(borderRadius: BorderRadius.circular(24),
          child: Stack(children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                t.surface.withValues(alpha: .48),
                t.surface.withValues(alpha: .22),
                t.surface.withValues(alpha: .04)],
              stops: const [0, .51, 1])))),
            Positioned(left: 20, top: 22, right: narrow ? 66 : 270,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    StellarPlanetGlyph(size: 43),
                    const SizedBox(width: 8),
                    Flexible(child: Text(active
                        ? '当前航线 · FlClash' : '等待第一份配置',
                      maxLines: 2, style: TextStyle(color: t.text,
                        fontWeight: FontWeight.bold, fontSize: 20))),
                  ]),
                  const SizedBox(height: 13),
                  Text(
                    used == null || total == null
                        ? '流量配额未提供'
                        : '${_humanBytes(used)} / ${_humanBytes(total)}',
                    maxLines: 1, style: TextStyle(color: t.text,
                      fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 10),
                  SizedBox(width: narrow ? 178 : 315,
                    child: LinearProgressIndicator(
                      value: percent ?? 0, minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: t.line,
                      color: t.accent,
                    )),
                  const SizedBox(height: 9),
                  StellarLabel(percent == null
                    ? '套餐未返回用量数据'
                    : '已用 ${(percent * 100).toStringAsFixed(1)}%'),
                ],
              )),
            Positioned(left: 20, bottom: 16, right: 18,
              child: Row(children: [
                Icon(Icons.hub_outlined, color: t.accent, size: 16),
                const SizedBox(width: 7),
                StellarLabel('${widget.subscription?.nodes.length ?? 0} 条节点'),
                const SizedBox(width: 15),
                Icon(Icons.access_time_rounded, color: t.accent, size: 16),
                const SizedBox(width: 5),
                Expanded(child: StellarLabel('更新于 ${_elapsed(updated)}')),
                if (online) const StellarLabel('● 正在使用', accent: true),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext context, {required bool selected,
      num? used, num? total, double? percent, required bool online}) {
    final t = VelaThemeRuntime.active;
    final sub = widget.subscription!;
    final remote = _native?.remoteProviderCount ?? 0;
    return StellarPanel(selected: selected, padding: const EdgeInsets.all(17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StellarPlanetGlyph(size: 58),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_native?.profileName ?? '当前配置', style: TextStyle(color: t.text,
                fontWeight: FontWeight.bold, fontSize: 19)),
              const SizedBox(height: 4),
              StellarLabel(online ? '● 正在连接' : '● 已载入 FlClash 核心',
                accent: true),
            ],
          )),
          PopupMenuButton<String>(
            tooltip: '配置菜单',
            onSelected: (action) {
              if (action == 'update') _refresh();
              if (action == 'replace') _openImporter();
              if (action == 'manage') _showManagement();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'update',
                  enabled: !online && !_busy,
                  child: const Text('更新当前配置')),
              const PopupMenuItem(value: 'replace',
                  child: Text('替换配置')),
              const PopupMenuItem(value: 'manage',
                  child: Text('保存和管理')),
            ],
          ),
        ]),
        const SizedBox(height: 17),
        if (percent != null && used != null && total != null) ...[
          Text('${_humanBytes(used)} / ${_humanBytes(total)}',
            style: TextStyle(color: t.text)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: percent, minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: t.line),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 15, runSpacing: 8, children: [
          _iconLabel(Icons.public_outlined, '${sub.nodes.length} 个节点'),
          _iconLabel(Icons.hub_outlined, '$remote 个在线提供者'),
          _iconLabel(Icons.schedule_outlined,
              _elapsed(sub.lastUpdatedAt)),
          _iconLabel(Icons.shield_outlined,
              sub.storedOnDevice ? '已加密保存' : '仅当前会话'),
        ]),
      ]),
    );
  }

  Widget _iconLabel(IconData icon, String label) {
    final t = VelaThemeRuntime.active;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: t.accent, size: 15),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: t.muted, fontSize: 12)),
    ]);
  }

  Widget _emptyProfile(BuildContext context) {
    final t = VelaThemeRuntime.active;
    return StellarPanel(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 33),
      child: Center(child: Column(children: [
        StellarPlanetGlyph(size: 75),
        const SizedBox(height: 14),
        Text('尚未添加航线配置', style: TextStyle(
          color: t.text, fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 5),
        const StellarLabel('支持 FlClash / Mihomo 配置和 HTTPS 订阅'),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: _openImporter,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加配置')),
      ])),
    ));
  }
}
