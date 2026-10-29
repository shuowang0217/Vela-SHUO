import 'dart:async';

import 'package:flutter/material.dart';

import 'vela_auto_route_watcher.dart';
import 'vela_exit_ip_monitor.dart';
import 'vela_layered_connectivity.dart';

/// Diagnostics are kept in memory only. No IP, route name, or error is logged.
class VelaNetworkDiagnostics extends StatefulWidget {
  const VelaNetworkDiagnostics({
    super.key,
    required this.monitor,
    this.layeredProbe,
    this.routeWatcher,
  });

  final VelaExitIpMonitor monitor;
  final VelaLayeredConnectivityProbe? layeredProbe;
  final VelaAutoRouteWatcher? routeWatcher;

  @override
  State<VelaNetworkDiagnostics> createState() =>
      _VelaNetworkDiagnosticsState();
}

class _VelaNetworkDiagnosticsState extends State<VelaNetworkDiagnostics> {
  bool _testing = false;
  VelaLayeredCheckResult? _result;

  Future<void> _checkConnectivity() async {
    final probe = widget.layeredProbe;
    if (probe == null || _testing || !widget.monitor.connected) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final result = await probe.run();
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watcher = widget.routeWatcher;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.monitor,
        ?watcher,
      ]),
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final monitor = widget.monitor;
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
                    ? monitor.lastCheckFailed
                        ? '上次有效，复检异常' : '已验证'
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
                width: 98,
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
                style: TextStyle(fontSize: 17,
                    fontWeight: FontWeight.w600))),
              OutlinedButton(
                key: const ValueKey('vela_network_recheck'),
                onPressed: monitor.connected && !monitor.loading
                    ? () => unawaited(monitor.refresh()) : null,
                child: const Text('重新检测 IP'),
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
            line('实际请求链',
                info == null ? '暂无' : info.chains.isEmpty
                  ? '内核未返回链路' : info.chains.join(' → ')),
            line('路由校验', monitor.routeValidation),
            if (info != null)
              line('路由版本', info.coreEpoch == null
                  ? '未知'
                  : '核心 ${info.coreEpoch} / 选择 ${info.picksVersion ?? 0}'),
            if (watcher != null) ...[
              line('自动组链路', watcher.signature == null
                  ? '尚未取得'
                  : watcher.displayChain),
              if (watcher.lastError != null)
                line('组状态', watcher.lastError!),
            ],
            if (monitor.failureReason != null)
              line('最近失败', monitor.failureReason!),
            const SizedBox(height: 5),
            Row(children: [
              OutlinedButton.icon(
                key: const ValueKey('vela_network_layered_check'),
                onPressed: monitor.connected && !_testing
                    ? _checkConnectivity : null,
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: Text(_testing ? '检查中…' : '检查 DNS / HTTPS'),
              ),
            ]),
            const SizedBox(height: 7),
            line('系统 DNS', _result?.dnsDetail ?? '尚未单独测试'),
            line('内核 HTTPS', _result?.httpsDetail ?? '尚未单独测试'),
            Text(
              'DNS 指系统解析，不代表 Mihomo 内置 DNS；HTTPS 检测通过'
              '原生代理内核发起。自动组只观察当前选择成员，'
              '不同域名的规则出口可能不同。',
              style: TextStyle(color: colors.onSurfaceVariant,
                  fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 5),
            Text(
              '不保存、上传 IP、节点链路或订阅信息。'
              'IP 正常每 2 分钟复检，旧结果最多保留约 6 分钟。',
              style: TextStyle(color: colors.onSurfaceVariant,
                  fontSize: 11, height: 1.4),
            ),
          ],
        );
      },
    );
  }
}
