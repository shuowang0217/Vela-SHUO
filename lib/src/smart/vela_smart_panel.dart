// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:ui';
import 'package:flutter/material.dart';

import '../subscription/vela_subscription_controller.dart';
import '../theme/vela_palettes.dart';
import '../brand/vela_watercolor_chrome.dart';
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
          content: Text('本轮将测试 ' + count.toString() +
              ' 个节点。真实 HTTPS 限时下载的流量随速度变化；'
              '单次采样最多 16 MiB，失败时可能尝试备用源，'
              '最快候选还会复测。仍要开始吗？'),
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
          child: VelaWatercolorSurface(
        radius: 18,
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('航海罗盘 · 智能优选',
                style: TextStyle(color: theme.text,
                    fontWeight: FontWeight.w600, fontFamily: 'Georgia', fontSize: 17)),
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
              subtitle: Text('每' + e.scanIntervalMinutes.toString() +
                  '分钟检查 · 下载速度提升至少' +
                  e.minimumImprovementPercent.toString() + '%才考虑改选',
                  style: TextStyle(color: theme.muted, fontSize: 11)),
              onChanged: e.setAutoPick,
            ),
            Wrap(
              spacing: 16, runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('检测间隔',
                      style: TextStyle(color: theme.muted, fontSize: 12)),
                  const SizedBox(width: 7),
                  DropdownButton<int>(
                    key: const ValueKey('smart_scan_interval'),
                    value: e.scanIntervalMinutes,
                    items: [
                      for (final minutes in VelaSmartController.scanIntervalChoices)
                        DropdownMenuItem<int>(
                            value: minutes,
                            child: Text(minutes.toString() + ' 分钟')),
                    ],
                    onChanged: (value) {
                      if (value != null) e.setScanIntervalMinutes(value);
                    },
                  ),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('速度提升阈值',
                      style: TextStyle(color: theme.muted, fontSize: 12)),
                  const SizedBox(width: 7),
                  DropdownButton<int>(
                    key: const ValueKey('smart_speed_improvement'),
                    value: e.minimumImprovementPercent,
                    items: [
                      for (final percent in VelaSmartController.improvementChoices)
                        DropdownMenuItem<int>(
                            value: percent,
                            child: Text(percent.toString() + '%')),
                    ],
                    onChanged: (value) {
                      if (value != null) e.setMinimumImprovementPercent(value);
                    },
                  ),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('切换冷却',
                      style: TextStyle(color: theme.muted, fontSize: 12)),
                  const SizedBox(width: 7),
                  DropdownButton<int>(
                    key: const ValueKey('smart_switch_cooldown'),
                    value: e.switchCooldownMinutes,
                    items: [
                      for (final minutes in VelaSmartController.cooldownChoices)
                        DropdownMenuItem<int>(
                            value: minutes,
                            child: Text(minutes == 0 ? '不限制'
                                : minutes.toString() + ' 分钟')),
                    ],
                    onChanged: (value) {
                      if (value != null) e.setSwitchCooldownMinutes(value);
                    },
                  ),
                ]),
              ],
            ),
            Text('自动设置会保存。只在程序运行期间检测；已连接时通过'
                '原生内核验证并切换线路，失败则按原切换逻辑回退。',
                style: TextStyle(color: theme.muted, fontSize: 11)),
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
            Text('测速使用真实 HTTPS 限时流式下载，实际流量因速度而异；'
                 '最快候选会额外复测。启用智能优选后，可在已连接时通过'
                 '原生核心在线切换；手动指定节点后需点击恢复自动优选。',
                style: TextStyle(color: theme.muted, fontSize: 11)),
          ],
        ),
      )));
    },
  );

  static String _measure(VelaSmartController e, int i) {
    final delay = e.resultAt(i)?.lastMs;
    final download = e.downloadAt(i);
    final delayLabel = delay == null ? '—' : '$delay ms';
    if (e.isDownloadTesting(i)) {
      return '下载测速中… · $delayLabel';
    }
    // A finished latency probe does not imply the download has been run.
    // During a serial sweep most nodes are still queued, not failed.
    if (download == null) {
      final pending = e.scanning && e.scanKind != 'latency';
      return '${pending ? '待下载测速' : '未测下载速度'} · $delayLabel';
    }
    final speed = download.megabytesPerSecond;
    if (!download.ok || speed == null || speed <= 0) {
      return '${download.failureLabel} · $delayLabel';
    }
    return '${speed.toStringAsFixed(2)} MB/s' +
        (download.verified ? ' · 已复测' : ' · 初测') +
        ' · $delayLabel';
  }
}
