import 'dart:async';

import 'package:flutter/material.dart';

import 'vela_exit_ip_monitor.dart';

/// Session-only troubleshooting; no IPs or route names are persisted or sent.
class VelaNetworkDiagnostics extends StatelessWidget {
  const VelaNetworkDiagnostics({super.key, required this.monitor});

  final VelaExitIpMonitor monitor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: monitor,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final info = monitor.info;
      final verified = monitor.verifiedAt;
      final mode = switch (monitor.routeMode) {
        'direct' => '直连',
        'global' => '全局',
        _ => '规则',
      };
      final state = !monitor.connected
          ? '未连接'
          : monitor.loading && info == null
              ? '正在验证'
              : info != null
                  ? monitor.lastCheckFailed ? '上次有效，复检异常' : '已验证'
                  : '未验证';
      final time = verified == null
          ? '尚未验证'
          : verified.toLocal().toIso8601String()
              .substring(0, 16).replaceFirst('T', ' ');
      Widget line(String label, String detail) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 94,
              child: Text(label, style: TextStyle(
                color: colors.onSurfaceVariant, fontSize: 12)),
            ),
            Expanded(child: Text(detail, style: TextStyle(
              color: colors.onSurface, fontSize: 12))),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.network_check_rounded, color: colors.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('网络诊断',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            OutlinedButton(
              key: const ValueKey('vela_network_recheck'),
              onPressed: monitor.connected && !monitor.loading
                  ? () => unawaited(monitor.refresh()) : null,
              child: const Text('重新检测'),
            ),
          ]),
          const SizedBox(height: 12),
          line('连接状态', monitor.connected ? '内核线路已连接' : '未连接'),
          line('航线模式', mode),
          line('IP 检测', state),
          line('最近有效时间', time),
          line('检测源', info?.source == null
              ? '未取得有效结果'
              : Uri.tryParse(info!.source!)?.host ?? '检测服务'),
          line('真实出口链',
              info == null ? '暂无' : info.chains.isEmpty
                ? '内核未返回链路' : info.chains.join(' → ')),
          line('路由校验', monitor.routeValidation),
          if (info != null)
            line('路由版本', info.coreEpoch == null
                ? '未知'
                : '核心 ${info.coreEpoch} / 选择 ${info.picksVersion ?? 0}'),
          if (monitor.failureReason != null)
            line('最近失败', monitor.failureReason!),
          line('DNS 检测', '未单独测试；IP 检测使用 HTTPS'),
          const SizedBox(height: 3),
          Text(
            '仅显示本次运行中的网络状态；不保存、上传 IP、节点链路或订阅信息。'
            '连续复检失败时，旧 IP 最多保留约 6 分钟。',
            style: TextStyle(color: colors.onSurfaceVariant,
              fontSize: 11, height: 1.4),
          ),
        ],
      );
    },
  );
}
