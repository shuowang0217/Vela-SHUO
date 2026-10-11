import 'dart:io';

import 'package:flutter/material.dart';

import '../core/vela_core_controller.dart';
import '../android/vela_android_vpn.dart';
import '../theme/vela_palettes.dart';
import 'vela_subscription_controller.dart';
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
  bool _showUrl = false;
  bool _offlineMode = false;

  @override
  void dispose() {
    _url.clear();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.core]),
    builder: (context, _) {
      final colors = VelaThemeRuntime.active;
      final subscription = widget.controller;
      final core = widget.core;
      final busy = subscription.loading || subscription.vaultBusy ||
          core.busy || core.isListening || widget.androidVpn?.active == true;
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
                  ],
                ),
              ],
            ),
            TextField(
              key: const ValueKey('subscription_url_input'),
              controller: _url,
              enabled: !busy,
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
              onPressed: busy ? null : () async {
                final value = _url.text.trim();
                if (value.isEmpty) {
                  return;
                }
                if (_offlineMode) {
                  await subscription.importFromText(value);
                } else {
                  await subscription.importFromUrl(value);
                }
                // Do not retain subscription access tokens in text input.
                if (mounted) {
                  _url.clear();
                }
              },
              icon: const Icon(Icons.download_rounded, size: 19),
              label: Text(subscription.loading ? '正在导入…' :
                  _offlineMode ? '解析节点' : '导入订阅'),
            ),
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
            Text('星标收藏仅调整列表顺序，不会自动切换节点。'
                '如需重启保留收藏，点击「加密保存本机」或「更新加密存档」。'
                '订阅及收藏仅通过系统安全存储加密保存，不保存订阅 URL。',
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
                    ? '更新加密存档' : '加密保存本机'),
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
              '节点的部分 Clash/Mihomo YAML、sing-box JSON 格式。'
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
