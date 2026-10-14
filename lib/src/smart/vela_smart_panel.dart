// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:ui';
import 'package:flutter/material.dart';

import '../subscription/vela_subscription_controller.dart';
import '../theme/vela_palettes.dart';
import 'vela_smart_controller.dart';
import 'vela_smart_country.dart';

class VelaSmartPanel extends StatefulWidget {
  const VelaSmartPanel({
    super.key, required this.engine, required this.subscription,
  });
  final VelaSmartController engine;
  final VelaSubscriptionController subscription;
  @override
  State<VelaSmartPanel> createState() => _VelaSmartPanelState();
}

class _VelaSmartPanelState extends State<VelaSmartPanel> {
  int _shown = 40;

  Future<void> _run() async {
    final smart = widget.engine;
    if (!smart.canTestAll) { return; }
    final count = smart.aiMode
        ? widget.subscription.nodes.where(
            (n) => velaSmartCountryMatches(n.name, smart.country)).length
        : smart.count;
    if (count > 50) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('确认全节点测速流量'),
          content: Text('本轮预计测试 ' + count.toString() +
              ' 个节点，每个约下载 1 MiB，总共约 ' +
              count.toString() + ' MiB（另有协议开销）。仍要开始吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false),
                child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('开始测速')),
          ],
        ),
      );
      if (ok != true || !mounted) { return; }
    }
    await smart.testAllNodes();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.engine, widget.subscription]),
    builder: (context, _) {
      final e = widget.engine;
      final s = widget.subscription;
      final theme = VelaThemeRuntime.active;
      final selected = s.selectedIndex;
      final candidates = e.sortedIndices.where((i) =>
          !e.aiMode || velaSmartCountryMatches(s.nodes[i].name, e.country))
          .toList();
      final rank = candidates.take(_shown).toList();
      final speed = selected == null
          ? null : e.downloadAt(selected)?.megabytesPerSecond;
      final last = e.lastScan;
      final checkedAt = last == null ? '—'
          : last.month.toString() + '/' + last.day.toString() + ' ' +
            last.hour.toString().padLeft(2, '0') + ':' +
            last.minute.toString().padLeft(2, '0');
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha:
               theme.dark ? .75 : .84),
          border: Border.all(color: theme.line.withValues(alpha: theme.dark ? .68 : .78)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SHUO Smart · 智能航线优选',
                style: TextStyle(color: theme.text,
                    fontWeight: FontWeight.w600, fontSize: 17)),
            const SizedBox(height: 8),
            Text('当前节点：' + (s.selected?.name ?? '未选择') +
                '  ·  下载速度：' +
                (speed == null ? '—' : speed.toStringAsFixed(2) + ' MB/s'),
                style: TextStyle(color: theme.muted, fontSize: 12)),
            Text('最近检测：' + checkedAt +
                '  ·  状态：' + (e.manualHold
                    ? '手动保持' : e.autoPickWhenIdle
                    ? '自动优选' : '手动优选'),
                style: TextStyle(color: theme.muted, fontSize: 12)),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              key: const ValueKey('smart_auto_pick'),
              contentPadding: EdgeInsets.zero,
              value: e.autoPickWhenIdle,
              title: Text('启用智能优选',
                  style: TextStyle(color: theme.text)),
              subtitle: Text('每10分钟检查 · 下载速度提升至少20%才考虑改选',
                  style: TextStyle(color: theme.muted, fontSize: 11)),
              onChanged: e.setAutoPick,
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('smart_ai_mode'),
              contentPadding: EdgeInsets.zero,
              value: e.aiMode,
              title: Text('AI 模式 · 单国家优选',
                  style: TextStyle(color: theme.text)),
              subtitle: Text('只筛选所选国家，首次优选不受20%限制',
                  style: TextStyle(color: theme.muted, fontSize: 11)),
              onChanged: e.setAiMode,
            ),
            if (e.aiMode) Wrap(
              spacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('固定国家/地区',
                    style: TextStyle(color: theme.muted, fontSize: 12)),
                DropdownButton<String>(
                  key: const ValueKey('smart_country'),
                  value: e.country,
                  items: [
                    for (final item in velaSmartCountries.entries)
                      DropdownMenuItem(
                          value: item.key, child: Text(item.value)),
                  ],
                  onChanged: (v) {
                    if (v != null) { e.setCountry(v); }
                  },
                ),
              ],
            ),
            if (e.manualHold)
              Row(children: [
                Expanded(child: Text('已手动锁定，自动切换暂停',
                    style: TextStyle(color: theme.muted, fontSize: 11))),
                TextButton.icon(
                  key: const ValueKey('smart_resume_auto'),
                  onPressed: e.resumeAutoSelection,
                  icon: const Icon(Icons.play_arrow, size: 17),
                  label: const Text('恢复自动优选'),
                ),
              ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('smart_measure_all'),
                onPressed: e.canTestAll ? _run : null,
                icon: const Icon(Icons.speed_rounded, size: 19),
                label: Text(e.scanning ? '测速进行中…'
                    : '一键测速 · 全节点延迟 + 下载速度'),
              ),
            ),
            if (e.scanning) Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('smart_cancel_scan'),
                onPressed: e.cancelling ? null : e.cancelScan,
                icon: const Icon(Icons.stop_circle_outlined, size: 17),
                label: Text(e.cancelling ? '正在停止…' : '停止测速'),
              ),
            ),
            if (e.scanning || e.total > 0) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                key: const ValueKey('smart_scan_progress'),
                value: e.total == 0 ? 0 : e.scanned / e.total,
                minHeight: 7,
              ),
              const SizedBox(height: 7),
              Text('已测 ' + e.scanned.toString() + '/' +
                  e.total.toString() + ' · 成功 ' +
                  e.successful.toString() + ' · 失败 ' +
                  e.failed.toString(),
                  style: TextStyle(color: theme.muted, fontSize: 12)),
            ],
            const SizedBox(height: 10),
            Text(e.status ?? '点击一次同时测所有节点的延迟与下载速度；'
                '当前连接不会被测速断开。',
                style: TextStyle(color: theme.muted, fontSize: 12)),
            const SizedBox(height: 14),
            Divider(color: theme.line),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('速度排行榜',
                  style: TextStyle(color: theme.text,
                      fontWeight: FontWeight.w600))),
              Text('下载 MB/s · 延迟 ms',
                  style: TextStyle(color: theme.muted, fontSize: 11)),
            ]),
            const SizedBox(height: 6),
            for (final i in rank) Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                if (e.recommendedIndex == i)
                  Icon(Icons.stars_rounded, size: 16, color: theme.accent),
                Expanded(child: Text(s.nodes[i].name, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.text, fontSize: 12,
                      fontWeight: selected == i
                          ? FontWeight.bold : FontWeight.normal))),
                const SizedBox(width: 8),
                Text(_measure(e, i),
                  style: TextStyle(fontSize: 11,
                      color: e.downloadAt(i)?.ok == true
                          ? theme.accent : theme.muted)),
              ]),
            ),
            if (candidates.length > rank.length)
              TextButton.icon(
                key: const ValueKey('smart_show_more'),
                onPressed: () => setState(() {
                  _shown = (_shown + 40).clamp(40, e.count);
                }),
                icon: const Icon(Icons.expand_more, size: 17),
                label: Text('显示更多（剩余 ' +
                    (candidates.length - rank.length).toString() + ' 个）'),
              ),
            if (_shown > 40) TextButton(
              key: const ValueKey('smart_collapse_results'),
              onPressed: () => setState(() { _shown = 40; }),
              child: const Text('收起结果'),
            ),
            if (e.history.isNotEmpty)
              ExpansionTile(
                key: const ValueKey('smart_selection_history'),
                tilePadding: EdgeInsets.zero,
                title: Text('优选与手动切换记录',
                    style: TextStyle(color: theme.text, fontSize: 12)),
                children: [
                  for (final entry in e.history.take(20))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(entry, style:
                            TextStyle(color: theme.muted, fontSize: 11)),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Text('测速下载每节点约1 MiB；使用 HTTPS 完整请求计时。'
                 '自动模式只在空闲时更新所选节点，'
                 '暂不支持 sing-box 在线无缝热切换。',
                style: TextStyle(color: theme.muted, fontSize: 11)),
          ],
        ),
      )));
    },
  );

  static String _measure(VelaSmartController e, int i) {
    final delay = e.resultAt(i)?.lastMs;
    final download = e.downloadAt(i);
    if (delay == null && download == null) { return '未测试'; }
    final speed = download?.megabytesPerSecond;
    return (speed == null || speed <= 0
        ? '下载失败' : speed.toStringAsFixed(2) + ' MB/s') +
        ' · ' + (delay == null ? '—' : delay.toString() + ' ms');
  }
}
