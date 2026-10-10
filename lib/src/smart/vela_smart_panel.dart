import 'package:flutter/material.dart';

import '../subscription/vela_subscription_controller.dart';
import '../theme/vela_palettes.dart';
import 'vela_smart_controller.dart';

/// Real test results only: never displays the demo node "latency" or Mbps.
class VelaSmartPanel extends StatelessWidget {
  const VelaSmartPanel({
    super.key,
    required this.engine,
    required this.subscription,
  });

  final VelaSmartController engine;
  final VelaSubscriptionController subscription;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([engine, subscription]),
    builder: (context, _) {
      final theme = VelaThemeRuntime.active;
      final selected = subscription.selectedIndex;
      final preferred = engine.recommendedIndex;
      final available = engine.count;
      final ranked = engine.sortedIndices.take(16).toList();
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(color: theme.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SHUO Smart Engine · v0.3 Alpha',
              style: TextStyle(color: theme.text,
                fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            Text(
              '对每个节点独立启动临时代理，通过真实 HTTPS 请求计时；'
              '不使用虚构延迟，不会改变现有 Windows 系统代理。',
              style: TextStyle(fontSize: 12, height: 1.5,
                color: theme.muted),
            ),
            const SizedBox(height: 13),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              key: const ValueKey('smart_auto_pick'),
              title: Text('空闲时自动选择优选节点',
                  style: TextStyle(color: theme.text)),
              subtitle: Text('仅在未连接时更新节点选择；绝不自动建立或切断连接',
                  style: TextStyle(fontSize: 11, color: theme.muted)),
              value: engine.autoPickWhenIdle,
              onChanged: engine.setAutoPick,
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 9, runSpacing: 9, children: [
              FilledButton.icon(
                key: const ValueKey('smart_measure_batch'),
                onPressed: engine.scanning || !engine.core.hasCore ||
                    engine.connection.busy ||
                    engine.connection.proxy.active ||
                    engine.core.isListening || available == 0
                    ? null : engine.testNextBatch,
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: Text(engine.scanning
                    ? '测速中 ${engine.scanned}/${engine.total}'
                    : '测试下一批（最多8个）'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('smart_use_recommended'),
                onPressed: engine.canRecommend
                    ? engine.useRecommended : null,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('选择推荐节点'),
              ),
            ]),
            const SizedBox(height: 10),
            Text(engine.status ?? (available == 0
                ? '请先在「设置」页面导入订阅。'
                : '尚未测速 · 可用节点 $available 个'),
              style: TextStyle(color: theme.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Text('启用冷却：3 分钟 · 需要至少改善 20% 且 50ms 才建议换节点。'
              '失败节点降权，当前连接始终受到保护。',
              style: TextStyle(color: theme.muted, fontSize: 11)),
            const SizedBox(height: 15),
            Divider(color: theme.line),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: Text('节点',
                style: TextStyle(color: theme.muted, fontSize: 12))),
              Text('HTTPS 耗时 / 结果',
                style: TextStyle(color: theme.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 7),
            for (final i in ranked)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  if (preferred == i)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.stars_rounded,
                        size: 15, color: theme.accent),
                    ),
                  Expanded(child: Text(subscription.nodes[i].name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text, fontSize: 12,
                      fontWeight: selected == i
                          ? FontWeight.bold : FontWeight.normal,
                    ))),
                  const SizedBox(width: 10),
                  Text(_label(engine.resultAt(i)),
                    style: TextStyle(
                      color: engine.resultAt(i)?.reachable == true
                          ? theme.accent : theme.muted,
                      fontSize: 12,
                    )),
                ]),
              ),
            if (available > ranked.length)
              Text('仅显示前 ${ranked.length} 个，'
                '继续测速可更新排序。总节点数 $available。',
                style: TextStyle(color: theme.muted, fontSize: 11)),
            const SizedBox(height: 12),
            Text('延迟为经过代理的单次 HTTPS 完整响应耗时，'
              '不代表游戏 Ping、下载 Mbps 或所有网站的实际速度。',
              style: TextStyle(color: theme.muted, fontSize: 11, height: 1.5)),
          ],
        ),
      );
    },
  );

  static String _label(VelaNodeHealth? health) {
    if (health == null) return '未测试';
    if (!health.reachable) {
      return '失败 ×${health.consecutiveFailures}';
    }
    return '${health.lastMs} ms';
  }
}
