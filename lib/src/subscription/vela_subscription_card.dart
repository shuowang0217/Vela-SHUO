import 'dart:io';

import 'package:flutter/material.dart';

import '../core/vela_core_controller.dart';
import '../theme/vela_palettes.dart';
import 'vela_subscription_controller.dart';

/// Subscription credentials never enter a diagnostic log or persisted field.
class VelaSubscriptionCard extends StatefulWidget {
  const VelaSubscriptionCard({
    super.key,
    required this.controller,
    required this.core,
  });

  final VelaSubscriptionController controller;
  final VelaCoreController core;

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
      final busy = subscription.loading || core.busy || core.isListening;
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
                Platform.isAndroid ? '订阅浏览 · Android 预览版' :
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
                  '内容仅在本次应用会话中解析，不会建立 VPN 连接。'
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
            if (!_offlineMode) Wrap(
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
                    if (mode != null) subscription.setDownloadMode(mode);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: VelaSubscriptionDownloadMode.automatic,
                      child: Text('自动（系统代理优先，失败后直连）'),
                    ),
                    if (!Platform.isAndroid) DropdownMenuItem(
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
                if (value.isEmpty) return;
                if (_offlineMode) {
                  await subscription.importFromText(value);
                } else {
                  await subscription.importFromUrl(value);
                }
                // Do not retain subscription access tokens in text input.
                if (mounted) _url.clear();
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 330),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: subscription.nodes.length,
                  itemBuilder: (context, i) {
                    final node = subscription.nodes[i];
                    final selected = subscription.selectedIndex == i;
                    return ListTile(
                      dense: true,
                      key: ValueKey('subscription_node_$i'),
                      enabled: !busy,
                      selected: selected,
                      contentPadding: EdgeInsets.zero,
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
              const SizedBox(height: 9),
              if (subscription.selected != null) Text(
                Platform.isAndroid
                    ? '已选：${subscription.selected!.name} · 仅预览，不提供 VPN'
                    : '已选择：${subscription.selected!.name} · '
                      '现在可以点击下方「启动本地代理」',
                style: TextStyle(color: colors.accent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '目前支持常见 Shadowsocks、VMess、VLESS、Trojan 和 Hysteria2 '
              '节点的部分 Clash/Mihomo YAML、sing-box JSON 格式。'
              '证书校验被关闭或不支持的传输参数会被跳过。'
              Platform.isAndroid
                  ? 'Android 预览版不会安装 VPN Service、运行 Mihomo 或改变网络设置。'
                  : '导入与节点选择不会自动接管 Windows 系统流量。',
              style: TextStyle(color: colors.muted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      );
    },
  );
}
