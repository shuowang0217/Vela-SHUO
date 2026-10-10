import 'package:flutter/material.dart';

import '../subscription/vela_subscription_controller.dart';
import '../theme/vela_palettes.dart';
import 'vela_smart_controller.dart';

/// Full subscription benchmark view. No demo delays or fake bandwidth.
class VelaSmartPanel extends StatefulWidget {
  const VelaSmartPanel({
    super.key,
    required this.engine,
    required this.subscription,
  });

  final VelaSmartController engine;
  final VelaSubscriptionController subscription;

  @override
  State<VelaSmartPanel> createState() => _VelaSmartPanelState();
}

class _VelaSmartPanelState extends State<VelaSmartPanel> {
  int _shown = 40;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.engine, widget.subscription]),
    builder: (context, _) {
      final engine = widget.engine;
      final subscription = widget.subscription;
      final theme = VelaThemeRuntime.active;
      final selected = subscription.selectedIndex;
      final preferred = engine.recommendedIndex;
      final available = engine.count;
      final ranked = engine.sortedIndices.take(_shown).toList();

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
            Text('SHUO Smart Engine · 全节点测速',
              style: TextStyle(color: theme.text,
                fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            Text(
              '一键检测整份订阅。独立临时代理发送真实 HTTPS 请求，'
              '每次最多同时检测两个节点，不更改当前 Windows 系统代理。',
              style: TextStyle(fontSize: 12, height: 1.5,
                color: theme.muted),
            ),
            const SizedBox(height: 13),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              key: const ValueKey('smart_auto_pick'),
              title: Text('空闲时自动选择优选节点',
                  style: TextStyle(color: theme.text)),
              subtitle: Text('仅断开状态下更换所选节点，不自动建立或中断连接',
                  style: TextStyle(fontSize: 11, color: theme.muted)),
              value: engine.autoPickWhenIdle,
              onChanged: engine.setAutoPick,
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 9, runSpacing: 9, children: [
              FilledButton.icon(
                key: const ValueKey('smart_measure_all'),
                onPressed: engine.canTestAll ? engine.testAllNodes : null,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('一键测速全部节点'),
              ),
              if (engine.scanning)
                OutlinedButton.icon(
                  key: const ValueKey('smart_cancel_scan'),
                  onPressed: engine.cancelling ? null : engine.cancelScan,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(engine.cancelling ? '正在停止…' : '停止测速'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('smart_measure_batch'),
                onPressed: engine.scanning || !engine.core.hasCore ||
                    engine.connection.busy ||
                    engine.connection.proxy.active ||
                    engine.core.isListening || available == 0
                    ? null : engine.testNextBatch,
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: const Text('测试下一批（最多8个）'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('smart_use_recommended'),
                onPressed: engine.canRecommend
                    ? engine.useRecommended : null,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('选择推荐节点'),
              ),
            ]),
            const SizedBox(height: 12),
            if (engine.scanning || engine.total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  key: const ValueKey('smart_scan_progress'),
                  value: engine.total == 0
                      ? 0 : engine.scanned / engine.total,
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(spacing: 12, runSpacing: 4, children: [
                Text('进度 ${engine.scanned} / ${engine.total}',
                    style: TextStyle(color: theme.text, fontSize: 12)),
                Text('成功 ${engine.successful}',
                    style: TextStyle(color: theme.accent, fontSize: 12)),
                Text('失败 ${engine.failed}',
                    style: TextStyle(color: theme.muted, fontSize: 12)),
                Text('剩余 ${engine.total - engine.scanned}',
                    style: TextStyle(color: theme.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
            ],
            Text(engine.status ?? (available == 0
                ? '请先在「设置」页面导入订阅。'
                : '尚未测速 · 总计 $available 个节点'),
              style: TextStyle(color: theme.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Text('可在保持连接时测速，但不切换当前线路。'
              '改选仍需满足3分钟冷却、改善至少20%且50ms的门槛。',
              style: TextStyle(color: theme.muted, fontSize: 11)),
            const SizedBox(height: 15),
            Divider(color: theme.line),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: Text('全部节点（按实测结果排序）',
                style: TextStyle(color: theme.muted, fontSize: 12))),
              Text('HTTPS 耗时 / 结果',
                style: TextStyle(color: theme.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 7),
            for (final i in ranked)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
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
              TextButton.icon(
                key: const ValueKey('smart_show_more'),
                onPressed: () => setState(() {
                  _shown = _shown + 40 < available ? _shown + 40 : available;
                }),
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text('显示更多（剩余 ${available - ranked.length} 个）'),
              ),
            if (_shown > 40)
              TextButton.icon(
                key: const ValueKey('smart_collapse_results'),
                onPressed: () => setState(() { _shown = 40; }),
                icon: const Icon(Icons.expand_less_rounded, size: 18),
                label: const Text('收起结果'),
              ),
            const SizedBox(height: 12),
            Text('显示的毫秒值为单次 HTTPS 完整请求耗时，'
              '不等于游戏 Ping、下载 Mbps 或其他网站的实际速度。',
              style: TextStyle(color: theme.muted, fontSize: 11, height: 1.5)),
          ],
        ),
      );
    },
  );

  static String _label(VelaNodeHealth? health) {
    if (health == null) { return '未测试'; }
    if (!health.reachable) {
      return '失败 ×${health.consecutiveFailures}';
    }
    return '${health.lastMs} ms';
  }
}
