import 'package:flutter/material.dart';
import '../brand/vela_glass_toast.dart';

import '../android/vela_android_vpn.dart';
import '../core/vela_connection_coordinator.dart';
import '../core/vela_core_controller.dart';
import '../home/demo_connection.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import '../subscription/vela_profile_library.dart';
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
    VelaGlassToast.show(context, message);
  }

  Future<void> _refresh({String? profileId}) async {
    if (_busy) return;
    final sub = widget.subscription;
    if (sub == null) return;
    setState(() => _busy = true);
    try {
      final native = _native;
      final id = profileId ?? native?.activeProfileId;
      bool ok = false;
      if (native != null && id != null) {
        final target = native.profiles.where((p) => p.id == id).firstOrNull;
        if (target?.sourceUrl != null) {
          ok = await native.refreshProfile(id);
        } else if (target != null && id == native.activeProfileId &&
            native.canRefreshProviders &&
            widget.connection?.connected != true &&
            widget.androidVpn?.active != true) {
          ok = await native.refreshNativeProviders();
        } else {
          _notify('该机场尚未设置 HTTPS 更新地址，请从菜单中选择「编辑机场」');
          return;
        }
      } else if (sub.canRefresh) {
        ok = await sub.refreshLastUrl();
      }
      final connected = widget.connection?.connected == true ||
          widget.androidVpn?.active == true;
      _notify(ok
          ? connected ? '机场已更新到加密存档；重新连接后启用新配置'
              : '机场配置已更新'
          : sub.error ?? '更新失败，原订阅未改变');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openImporter() async {
    final controller = widget.subscription;
    final core = widget.core;
    if (controller == null || core == null) {
      _notify('航线服务尚未就绪');
      return;
    }
    final stage = widget.connection?.connected == true ||
        widget.connection?.proxy.active == true ||
        widget.androidVpn?.active == true || core.isListening;
    final imported = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VelaStellarImportDialog(
          controller: controller, stageOnly: stage),
    );
    if (!mounted) return;
    if (imported == true) {
      _notify(stage ? '已获取并自动保存新机场，原代理连接保持不变'
          : '新机场已自动保存，${controller.nodes.length} 个节点');
    }
  }

  Future<void> _activateAirport(String id) async {
    final native = _native;
    if (native == null || _busy || native.activeProfileId == id) return;
    final oldId = native.activeProfileId;
    final connection = widget.connection;
    final vpn = widget.androidVpn;
    final wasWindows = connection?.connected == true;
    final wasAndroid = vpn?.connected == true;
    setState(() => _busy = true);
    try {
      if (connection != null &&
          (connection.proxy.active || connection.core.isListening)) {
        if (!await connection.disconnect()) {
          _notify('系统代理未能安全断开，已取消机场切换');
          return;
        }
      }
      if (vpn?.active == true && !await vpn!.stop()) {
        _notify('VPN 未能安全停止，已取消机场切换');
        return;
      }
      final switched = await native.activateProfile(id);
      if (!switched) {
        if (wasWindows && connection != null) await connection.connect();
        if (wasAndroid && vpn != null) await vpn.start(native);
        _notify(native.error ?? '加载目标机场失败，已尝试恢复原线路');
        return;
      }
      if (wasWindows && connection != null) {
        if (!await connection.connect()) {
          if (oldId != null && await native.activateProfile(oldId)) {
            await connection.connect();
          }
          _notify('目标机场连接验证失败，已尝试恢复之前的机场');
          return;
        }
      }
      if (wasAndroid && vpn != null) {
        if (!await vpn.start(native)) {
          if (oldId != null && await native.activateProfile(oldId)) {
            await vpn.start(native);
          }
          _notify('新机场 VPN 启动失败，已尝试恢复旧机场');
          return;
        }
      }
      _notify((wasWindows || wasAndroid)
          ? '机场切换完成，已重新建立代理连接'
          : '已切换机场，下次连接将使用此机场');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askAirportName(String initial) async {
    final input = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context, builder: (dialog) => AlertDialog(
          title: const Text('重命名机场'),
          content: TextField(controller: input, maxLength: 64,
              autofocus: true,
              decoration: const InputDecoration(labelText: '机场名称')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('取消')),
            FilledButton(onPressed: () {
              final value = input.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialog, value);
            }, child: const Text('确定')),
          ],
        ),
      );
    } finally {
      input.dispose();
    }
  }

  Future<void> _editAirport(VelaStoredProfile profile) async {
    final native = _native;
    if (native == null) return;
    final name = TextEditingController(text: profile.name);
    final url = TextEditingController(text: profile.sourceUrl ?? '');
    final minutes = TextEditingController(
      text: (profile.autoUpdateMinutes ?? 1440).toString());
    var auto = profile.autoUpdateMinutes != null;
    try {
      final save = await showDialog<bool>(
        context: context, builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('编辑机场'),
            content: SizedBox(width: 420,
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: name, maxLength: 64,
                    decoration: const InputDecoration(labelText: '机场名称')),
                  TextField(controller: url,
                    keyboardType: TextInputType.url,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'HTTPS 订阅地址',
                      helperText: '含令牌的网址仅保存于系统加密存储')),
                  SwitchListTile.adaptive(
                    title: const Text('自动更新'),
                    contentPadding: EdgeInsets.zero,
                    value: auto,
                    onChanged: (v) => update(() => auto = v)),
                  if (auto)
                    TextField(controller: minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '更新间隔（分钟）',
                        helperText: '最少 15 分钟；打开软件时自动更新')),
                  const SizedBox(height: 8),
                  const Text('编辑订阅来源或更新策略不影响正在连接的代理。',
                    style: TextStyle(fontSize: 11)),
                ],
              ))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存')),
            ],
          ),
        ),
      );
      if (save != true) return;
      final rawUrl = url.text.trim();
      final interval = auto ? int.tryParse(minutes.text.trim()) : null;
      if (auto && interval == null) {
        _notify('请输入有效的自动更新分钟数');
        return;
      }
      final ok = await native.updateProfileSettings(profile.id,
        name: name.text.trim(),
        sourceUrl: rawUrl.isEmpty ? null : rawUrl,
        autoUpdateMinutes: interval);
      _notify(ok ? '机场编辑已保存，随时可以更新订阅'
          : native.error ?? '编辑失败');
    } finally {
      name.dispose();
      url.dispose();
      minutes.dispose();
    }
  }

  Future<void> _editYaml(VelaStoredProfile profile) async {
    final native = _native;
    if (native == null) return;
    final text = TextEditingController(text: profile.raw);
    try {
      final save = await showDialog<bool>(
        context: context, builder: (dialog) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 660),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Text('编辑 ${profile.name} 的 Mihomo 配置',
                  style: Theme.of(dialog).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('保存前验证 YAML。运行中的代理不会被热替换；'
                    '新配置将在重新切换或连接机场后生效。',
                  style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Expanded(child: TextField(
                  key: const ValueKey('airport_yaml_editor'),
                  controller: text, expands: true,
                  maxLines: null, minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Mihomo YAML',
                  ),
                )),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('取消')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('验证并保存')),
                ]),
              ]),
            ),
          ),
        ),
      );
      if (save != true) return;
      _notify(await native.editProfileYaml(profile.id, text.text)
          ? '配置已安全保存；如连接中，重新连接后启用'
          : native.error ?? '配置修改失败');
    } finally {
      text.dispose();
    }
  }

  Future<void> _handleAirportMenu(VelaStoredProfile profile,
      String action) async {
    final native = _native;
    if (native == null || _busy) return;
    if (action == 'switch') {
      await _activateAirport(profile.id);
    } else if (action == 'edit') {
      await _editAirport(profile);
    } else if (action == 'refresh') {
      await _refresh(profileId: profile.id);
    } else if (action == 'edit_yaml') {
      await _editYaml(profile);
    } else if (action == 'rename') {
      final name = await _askAirportName(profile.name);
      if (name != null) {
        _notify(await native.renameProfile(profile.id, name)
            ? '机场已重命名' : native.error ?? '无法修改机场名称');
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context, builder: (dialog) => AlertDialog(
          title: Text('删除 ${profile.name}？'),
          content: const Text('将删除此机场的加密存档，不会删除其他机场。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true),
                child: const Text('删除')),
          ],
        ),
      );
      if (confirmed != true) return;
      _notify(await native.removeProfile(profile.id)
          ? '已删除该机场' : native.error ?? '删除失败');
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
            const StellarSectionHeading('配置操作', '安全管理订阅、机场和航线'),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('更新当前配置'),
              enabled: _native?.activeProfileId != null ||
                  sub.canRefresh || _native?.canRefreshProviders == true,
              onTap: () { Navigator.pop(ctx); _refresh(); },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('加密保存本机'),
              subtitle: const Text('使用系统安全存储保存配置和订阅来源'),
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
              constraints: const BoxConstraints(maxWidth: 875),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 16 : 25, narrow ? 78 : 77,
                  narrow ? 16 : 25, narrow ? 110 : 106),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: StellarSectionHeading(
                        '配置管理', '每条航线，都有自己的目的地')),
                      if (!narrow)
                        StellarAction(label: '刷新配置',
                          icon: Icons.sync_rounded,
                          onPressed: _busy || !hasProfile
                            ? null : _refresh),
                    ]),
                    const SizedBox(height: 16),
                    _hero(context, narrow, hasProfile, online,
                      used, total, percent, updated),
                    const SizedBox(height: 12),
                    if (narrow)
                      Row(children: [
                        Expanded(child: StellarAction(
                          label: '刷新当前配置',
                          icon: Icons.refresh_rounded,
                          onPressed: _busy || !hasProfile
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
                    if (_native?.profiles.isNotEmpty == true)
                      LayoutBuilder(builder: (context, area) {
                        final profiles = [..._native!.profiles];
                        if (_sortRecent) {
                          profiles.sort((a, b) => (b.updatedAt ?? DateTime(1970))
                              .compareTo(a.updatedAt ?? DateTime(1970)));
                        }
                        final cardWidth = area.maxWidth >= 680
                            ? (area.maxWidth - 12) / 2 : area.maxWidth;
                        return Wrap(spacing: 12, runSpacing: 12,
                          children: [for (final profile in profiles)
                            SizedBox(width: cardWidth,
                              child: _profileCard(context, profile,
                                selected: profile.id == _native!.activeProfileId,
                                online: online &&
                                    profile.id == _native!.activeProfileId)),
                          ],
                        );
                      })
                    else _emptyProfile(context),
                    const SizedBox(height: 15),
                    StellarPanel(child: Row(children: [
                      StellarCompassGlyph(size: 46),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('开启下一段航线',
                            style: TextStyle(color: t.text,
                              fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 5),
                          const StellarLabel(
                              '导入机场订阅或配置文件 · 本机安全管理'),
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
                    StellarLabel('多机场独立加密保存；连接中可获取新机场。'
                        '切换正在使用的机场时会安全断开并自动重连，短暂中断流量。'),
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
      child: SizedBox(height: narrow ? 210 : 182,
        child: ClipRRect(borderRadius: BorderRadius.circular(24),
          child: Stack(children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                t.surface.withValues(alpha: .26),
                t.surface.withValues(alpha: .10),
                t.surface.withValues(alpha: .015)],
              stops: const [0, .51, 1])))),
            Positioned(left: 20, top: 20, right: 24,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    StellarCompassGlyph(size: 43),
                    const SizedBox(width: 8),
                    Flexible(child: Text(active
                        ? '当前航线 · ${_native?.profileName ?? '未命名机场'}' : '等待第一份配置',
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

  Widget _profileCard(BuildContext context, VelaStoredProfile profile, {
    required bool selected, required bool online,
  }) {
    final t = VelaThemeRuntime.active;
    final usage = profile.usage;
    final total = usage?['total'];
    final used = usage == null ? null :
        (usage['upload'] ?? 0) + (usage['download'] ?? 0);
    final fraction = total != null && total > 0 && used != null
        ? (used / total).clamp(0.0, 1.0).toDouble() : null;
    return InkWell(
      key: ValueKey('airport_card_${profile.id}'),
      borderRadius: BorderRadius.circular(18),
      onTap: _busy || selected ? null : () => _activateAirport(profile.id),
      child: StellarPanel(selected: selected,
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StellarCompassGlyph(size: 42),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.name, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.text,
                      fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 4),
                StellarLabel(online ? '● 代理正在使用'
                    : selected ? '● 当前机场' : '点击切换机场',
                    accent: selected),
              ])),
            PopupMenuButton<String>(
              key: ValueKey('airport_menu_${profile.id}'),
              tooltip: '机场操作',
              onSelected: (value) => _handleAirportMenu(profile, value),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'switch', enabled: !selected,
                    child: const Text('切换到此机场')),
                const PopupMenuItem(value: 'edit',
                    child: Text('编辑机场 · 地址和自动更新')),
                const PopupMenuItem(value: 'refresh',
                    child: Text('立即更新机场')),
                const PopupMenuItem(value: 'edit_yaml',
                    child: Text('编辑 Mihomo 配置')),
                const PopupMenuItem(value: 'rename',
                    child: Text('重命名机场')),
                const PopupMenuItem(value: 'delete',
                    child: Text('删除机场')),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          Text(used != null && total != null
              ? '${_humanBytes(used)} / ${_humanBytes(total)}'
              : '未提供套餐用量',
            style: TextStyle(color: t.text, fontSize: 13)),
          const SizedBox(height: 7),
          LinearProgressIndicator(value: fraction ?? 0, minHeight: 5,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: t.line, color: t.accent),
          const SizedBox(height: 11),
          Wrap(spacing: 12, runSpacing: 7, children: [
            if (profile.nodeCount != null)
              _iconLabel(Icons.hub_outlined, '${profile.nodeCount} 个节点'),
            _iconLabel(Icons.schedule_outlined,
                _elapsed(profile.updatedAt)),
            _iconLabel(Icons.lock_outline, '已加密保存'),
            if (profile.sourceUrl != null)
              _iconLabel(Icons.link, '可更新'),
            if (profile.autoUpdateMinutes != null)
              _iconLabel(Icons.autorenew,
                  '每 ${profile.autoUpdateMinutes} 分钟'),
          ]),
        ]),
      ),
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
        StellarCompassGlyph(size: 75),
        const SizedBox(height: 14),
        Text('尚未添加航线配置', style: TextStyle(
          color: t.text, fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 5),
        const StellarLabel('支持通用配置文件及 HTTPS 订阅'),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: _openImporter,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加配置')),
      ])),
    ));
  }
}
