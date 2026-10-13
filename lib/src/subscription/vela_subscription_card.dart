import 'dart:io';

import 'package:flutter/material.dart';

import '../core/vela_core_controller.dart';
import '../android/vela_android_vpn.dart';
import '../theme/vela_palettes.dart';
import 'vela_subscription_controller.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import 'vela_node_filter_panel.dart';

/// Subscription credentials never enter a diagnostic log or persisted field.
class VelaSubscriptionCard extends StatefulWidget {
  const VelaSubscriptionCard({
    super.key,
    required this.controller,
    required this.core,
    this.androidVpn,
  });

  final VelaSubscriptionController controller;
  final VelaCoreController core;
  final VelaAndroidVpnController? androidVpn;

  @override
  State<VelaSubscriptionCard> createState() => _VelaSubscriptionCardState();
}

class _VelaSubscriptionCardState extends State<VelaSubscriptionCard> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _localPort = TextEditingController();
  bool _showUrl = false;
  bool _offlineMode = false;

  @override
  void initState() {
    super.initState();
    final port = widget.controller.localHttpProxyPort;
    if (port != null) _localPort.text = port.toString();
  }

  Future<String?> _askProfileName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 64,
            decoration: const InputDecoration(
                labelText: '订阅名称', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) Navigator.of(dialog).pop(name);
              },
              child: const Text('保存')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value)));
  }

  @override
  void dispose() {
    _url.clear();
    _url.dispose();
    _localPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.core]),
    builder: (context, _) {
      final colors = VelaThemeRuntime.active;
      final subscription = widget.controller;
      final core = widget.core;
      final runtimeActive = core.isListening ||
          widget.androidVpn?.active == true;
      final busy = subscription.loading || subscription.vaultBusy ||
          core.busy || runtimeActive;
      final importingBusy = subscription.loading || subscription.vaultBusy ||
          core.busy || (_offlineMode && runtimeActive);
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: .94),
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.link_rounded, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(
                Platform.isAndroid ? 'Android VPN · 订阅节点管理' :
                    '订阅导入与节点管理 · Beta',
                style: TextStyle(
                  color: colors.text, fontWeight: FontWeight.w600, fontSize: 17,
                ),
              )),
            ]),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                ? '支持直接导入 HTTPS 订阅或粘贴节点分享链接。'
                  '导入不自动建立 VPN，需在首页明确授权连接。'
                : '在这里粘贴自己的 HTTPS 订阅链接或分享链接，'
                  '无需发到聊天里。不会保存访问密钥。',
              style: TextStyle(color: colors.muted, fontSize: 12, height: 1.55),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('HTTPS 订阅'),
                  selected: !_offlineMode, onSelected: busy ? null : (_) {
                    _url.clear();
                    setState(() => _offlineMode = false);
                  }),
              ChoiceChip(label: const Text('粘贴节点 / YAML'),
                  selected: _offlineMode, onSelected: busy ? null : (_) {
                    _url.clear();
                    setState(() => _offlineMode = true);
                  }),
            ]),
            if (!_offlineMode && !Platform.isAndroid) Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text('订阅下载方式',
                    style: TextStyle(color: colors.muted, fontSize: 12)),
                DropdownButton<VelaSubscriptionDownloadMode>(
                  key: const ValueKey('subscription_download_mode'),
                  value: subscription.downloadMode,
                  onChanged: busy ? null : (mode) {
                    if (mode != null) {
                      subscription.setDownloadMode(mode);
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: VelaSubscriptionDownloadMode.automatic,
                      child: Text('自动（系统代理优先，失败后直连）'),
                    ),
                    DropdownMenuItem(
                      value: VelaSubscriptionDownloadMode.systemProxy,
                      child: Text('仅使用 Windows 系统代理'),
                    ),
                    DropdownMenuItem(
                      value: VelaSubscriptionDownloadMode.direct,
                      child: Text('仅直连'),
                    ),
                    DropdownMenuItem(
                      value: VelaSubscriptionDownloadMode.localHttp,
                      child: Text('手动本机 HTTP/Mixed 代理端口'),
                    ),
                  ],
                ),
              ],
            ),
            if (!_offlineMode && Platform.isWindows &&
                subscription.downloadMode ==
                    VelaSubscriptionDownloadMode.localHttp) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('subscription_local_proxy_port'),
                controller: _localPort,
                enabled: !busy,
                maxLength: 5,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  subscription.setLocalHttpProxyPort(value);
                },
                decoration: const InputDecoration(
                  labelText: '本机 HTTP / Mixed 端口（例如 7890）',
                  helperText: '从已运行的代理软件中查看 HTTP 或 Mixed 端口；'
                      '仅 SOCKS5 端口不支持。不会修改 Windows 系统代理。',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (!subscription.localHttpProxyValid)
                Text('请输入有效端口，如 7890、7897、10809；'
                    '不能使用 Vela 自身端口。',
                  style: TextStyle(color: colors.muted, fontSize: 11)),
              const SizedBox(height: 9),
            ],
            TextField(
              key: const ValueKey('subscription_url_input'),
              controller: _url,
              enabled: !importingBusy,
              obscureText: !_showUrl && !_offlineMode,
              maxLines: _offlineMode ? 4 : 1,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _offlineMode
                    ? '分享链接 / Clash YAML（可能包含密钥）'
                    : 'HTTPS 订阅链接（可能包含访问密钥）',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showUrl ? '隐藏地址' : '显示地址',
                  onPressed: () => setState(() => _showUrl = !_showUrl),
                  icon: Icon(_showUrl
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('subscription_import'),
              onPressed: importingBusy ? null : () async {
                final value = _url.text.trim();
                if (value.isEmpty) {
                  return;
                }
                final ok = _offlineMode
                    ? await subscription.importFromText(value)
                    : subscription is VelaFlClashSubscriptionController
                        ? await subscription.importFromUrlNamed(value,
                            stageOnly: runtimeActive)
                        : await subscription.importFromUrl(value);
                // Do not retain subscription tokens in the visible input.
                if (context.mounted) {
                  if (ok) _url.clear();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? '机场获取成功，已自动加密保存'
                        : subscription.error ?? '获取机场失败'),
                  ));
                }
              },
              icon: const Icon(Icons.download_rounded, size: 19),
              label: Text(subscription.loading ? '正在导入…' :
                  _offlineMode ? '解析节点' : '导入订阅'),
            ),
            if (subscription.hasSessionUrl) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('subscription_manual_refresh'),
                onPressed: busy || !subscription.canRefresh ? null : () async {
                  final ok = await subscription.refreshLastUrl();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? '订阅已更新并自动保存'
                        : subscription.error ?? '订阅更新失败，原节点列表仍保留'),
                  ));
                },
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('重新获取订阅（仅本次运行）'),
              ),
              const SizedBox(height: 5),
              Text('仅在本次启动期间保留上次成功导入的 HTTPS 地址；'
                  '不写入本地存档、不自动更新，也不会自动启动代理或 VPN。',
                style: TextStyle(color: colors.muted, fontSize: 11)),
            ],
            if (subscription is VelaFlClashSubscriptionController) ...[
              const SizedBox(height: 18),
              Row(children: [
                Icon(Icons.folder_copy_outlined, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(child: Text('已保存的订阅',
                    style: TextStyle(color: colors.text,
                        fontWeight: FontWeight.w600))),
                Text('${subscription.profiles.length}/20',
                    style: TextStyle(color: colors.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('saved_profile_selector_${subscription.activeProfileId ?? 'unsaved'}'),
                initialValue: subscription.profiles.any(
                    (p) => p.id == subscription.activeProfileId)
                    ? subscription.activeProfileId : null,
                hint: const Text('选择已加密保存的订阅'),
                isExpanded: true,
                items: [
                  for (final p in subscription.profiles)
                    DropdownMenuItem(value: p.id,
                        child: Text(p.name,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: busy ? null : (id) async {
                  if (id == null) return;
                  final ok = await subscription.activateProfile(id);
                  _message(ok ? '已切换订阅（不会自动连接代理）'
                      : subscription.error ?? '切换失败');
                },
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  key: const ValueKey('save_new_subscription'),
                  onPressed: busy || !subscription.canSave ||
                      subscription.profiles.length >= 20 ? null : () async {
                    final name = await _askProfileName('另存为新订阅',
                        initial: subscription.profileName ?? '');
                    if (name == null) return;
                    final ok = await subscription.saveAsProfile(name);
                    _message(ok ? '订阅已加密保存，可随时切换'
                        : subscription.error ?? '保存失败');
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('另存为新订阅'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('rename_saved_subscription'),
                  onPressed: busy || subscription.activeProfileId == null
                      ? null : () async {
                    final id = subscription.activeProfileId!;
                    final name = await _askProfileName('重命名订阅',
                        initial: subscription.profileName ?? '');
                    if (name == null) return;
                    final ok = await subscription.renameProfile(id, name);
                    _message(ok ? '订阅已重命名' : '重命名失败');
                  },
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('重命名'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('remove_saved_subscription'),
                  onPressed: busy || subscription.activeProfileId == null
                      ? null : () async {
                    final id = subscription.activeProfileId!;
                    final accepted = await showDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const Text('删除已保存的订阅？'),
                        content: const Text(
                            '仅删除加密存档，不会修改当前已导入的节点；删除无法撤销。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialog).pop(false),
                            child: const Text('取消')),
                          FilledButton(
                            onPressed: () => Navigator.of(dialog).pop(true),
                            child: const Text('删除')),
                        ],
                      ),
                    );
                    if (accepted != true) return;
                    final ok = await subscription.removeProfile(id);
                    _message(ok ? '已删除该订阅的加密存档' : '删除失败');
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除当前存档'),
                ),
              ]),
              const SizedBox(height: 8),
              Text('切换订阅前请先断开代理或 VPN。每份存档分别保存节点选择与收藏；'
                  '原始订阅网址仍然仅保留在本次运行内。',
                  style: TextStyle(color: colors.muted, fontSize: 11)),
            ],
            // Native FlClash proxy-providers are separate from downloading
            // the outer subscription URL. Refreshes run in the Go backend
            // and retain the selected node / favorites by stable name.
            if (subscription is VelaFlClashSubscriptionController &&
                subscription.remoteProviderCount > 0) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('flclash_update_providers'),
                onPressed: busy || !subscription.canRefreshProviders
                    ? null : () async {
                  final ok = await subscription.refreshNativeProviders();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? '已更新远程航线节点，保留仍存在的选择和收藏'
                        : subscription.error ?? '节点提供者更新失败'),
                  ));
                },
                icon: const Icon(Icons.sync_rounded, size: 19),
                label: Text('更新远程航线节点 '
                    '(${subscription.remoteProviderCount})'),
              ),
            ],
            if (subscription.error != null) Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(subscription.error!,
                  style: const TextStyle(color: Color(0xFFD77874))),
            ),
            if (subscription.nodes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '识别到 ${subscription.nodes.length} 个节点 · '
                '跳过 ${subscription.skipped} 个 · '
                '${subscription.format ?? ''}',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              VelaNodeFilterPanel(
                controller: subscription,
                builder: (context, indices) => ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 330),
                  child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: indices.length,
                  itemBuilder: (context, position) {
                    final i = indices[position];
                    final node = subscription.nodes[i];
                    final selected = subscription.selectedIndex == i;
                    return ListTile(
                      dense: true,
                      key: ValueKey('subscription_node_$i'),
                      enabled: !busy,
                      selected: selected,
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        key: ValueKey('subscription_favorite_$i'),
                        tooltip: subscription.isFavorite(i)
                            ? '取消收藏' : '收藏节点',
                        onPressed: () => subscription.toggleFavorite(i),
                        icon: Icon(subscription.isFavorite(i)
                            ? Icons.star_rounded : Icons.star_border_rounded,
                          color: subscription.isFavorite(i)
                              ? colors.accent : colors.muted),
                      ),
                      title: Text(node.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.text)),
                      subtitle: Text(node.protocol,
                          style: TextStyle(color: colors.muted, fontSize: 11)),
                      trailing: Icon(
                        selected ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
                        color: selected ? colors.accent : colors.muted,
                      ),
                      onTap: busy ? null : () => subscription.selectNode(i),
                    );
                  },
                  ),
                ),
              ),
              const SizedBox(height: 9),
              if (subscription.selected != null) Text(
                Platform.isAndroid
                    ? '已选：${subscription.selected!.name} · 首页可授权并连接'
                    : '已选择：${subscription.selected!.name} · '
                      '现在可以点击下方「启动本地代理」',
                style: TextStyle(color: colors.accent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text('获取成功后机场自动加密保存；选择的节点与收藏也会自动保存。'
                '连接中可获取新机场，切换请在配置页点击目标机场。'
                '不会在本地保存原始订阅 URL。',
                style: TextStyle(color: colors.muted, fontSize: 11)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: const ValueKey('save_subscription_securely'),
                onPressed: !busy && subscription.canSave ? () async {
                  final saved = await subscription.saveOnDevice();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(saved ? '已加密保存到本机，重启后可恢复'
                        : subscription.error ?? '无法保存订阅'),
                  ));
                } : null,
                icon: const Icon(Icons.lock_outline),
                label: Text(subscription.storedOnDevice
                    ? '立即同步加密存档' : '手动补存档'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('clear_subscription_securely'),
                onPressed: busy ? null : () async {
                  final deleted = await subscription.clearSaved();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(deleted ? '已删除本机加密存档'
                        : subscription.error ?? '删除失败'),
                  ));
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除本机存档'),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              '目前支持常见 Shadowsocks、VMess、VLESS、Trojan 和 Hysteria2 '
              '节点的常见配置格式。'
              '证书校验被关闭或不支持的传输参数会被跳过。'
              '${Platform.isAndroid ? 'Android VPN 只会在首页点击授权连接后启动。' : '导入与节点选择不会自动接管 Windows 系统流量。'}',
              style: TextStyle(color: colors.muted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      );
    },
  );
}
