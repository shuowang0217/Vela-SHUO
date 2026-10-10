import 'package:flutter/material.dart';

import '../subscription/vela_subscription_controller.dart';
import 'vela_mihomo_lab_controller.dart';

/// Experimental settings-only surface. The production home connect button
/// still controls sing-box and its independently verified WinINet recovery.
class VelaMihomoLabCard extends StatelessWidget {
  const VelaMihomoLabCard({
    super.key, required this.lab, required this.subscription,
  });
  final VelaMihomoLabController lab;
  final VelaSubscriptionController subscription;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([lab, subscription]),
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      final selected = lab.running
          ? lab.selectedIndex : subscription.selectedIndex;
      final canLaunch = lab.hasBinary && !lab.busy && !lab.running &&
          selected != null && subscription.nodes.isNotEmpty;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.science_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Mihomo 独立内核实验室',
                  style: TextStyle(color: scheme.onSurface,
                      fontWeight: FontWeight.w600, fontSize: 16))),
                Text('EXPERIMENT', style: TextStyle(fontSize: 10,
                    color: scheme.tertiary)),
              ]),
              const SizedBox(height: 9),
              Text('与已验证的 sing-box 一键连接相互独立。仅占用本地 '
                  '127.0.0.1:20818（代理）、20819（控制 API），'
                  '不会接管 Windows 系统代理或修改首页连接状态。',
                style: TextStyle(fontSize: 12,
                    color: scheme.onSurfaceVariant, height: 1.5)),
              const SizedBox(height: 12),
              Text(lab.hasBinary ? lab.status : '实验内核未打包，主版本不受影响',
                  style: TextStyle(color: lab.running
                      ? scheme.primary : scheme.onSurfaceVariant)),
              if (lab.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(lab.error!, style: TextStyle(
                      color: scheme.error, fontSize: 12)),
                ),
              if (subscription.nodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButton<int>(
                  key: const ValueKey('mihomo_lab_node'),
                  isExpanded: true,
                  value: selected,
                  hint: const Text('先在订阅中选择一个节点'),
                  items: [
                    for (var i = 0; i < subscription.nodes.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(subscription.nodes[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: lab.busy || !lab.running ? null : (i) {
                    if (i != null) { lab.switchNode(i); }
                  },
                ),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 8, children: [
                FilledButton.icon(
                  key: const ValueKey('mihomo_lab_start'),
                  onPressed: canLaunch ? () {
                    lab.start(subscription.nodes, selected);
                  } : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('启动实验内核并验证 HTTPS'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('mihomo_lab_stop'),
                  onPressed: lab.running && !lab.busy ? lab.stop : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('停止 Mihomo 实验'),
                ),
              ]),
              if (lab.running) ...[
                const SizedBox(height: 12),
                Text('已验证节点：' + (lab.selectedName ?? '—') +
                    ' · 兼容节点 ' + lab.compatibleCount.toString() + ' 个',
                    style: TextStyle(color: scheme.onSurfaceVariant,
                        fontSize: 12)),
              ],
              const SizedBox(height: 8),
              Text('仅测试 Mihomo 策略组原位切换；无法保证已有 TCP/UDP '
                  '连接不中断。下一阶段才评估正式系统代理切换及 FlClash '
                  '定制版测速 API。请勿同时让两个内核接管系统代理。',
                  style: TextStyle(color: scheme.onSurfaceVariant,
                      fontSize: 11, height: 1.5)),
            ],
          ),
        ),
      );
    },
  );
}
