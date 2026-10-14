import 'package:file_selector/file_selector.dart';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/vela_palettes.dart';
import 'vela_core_controller.dart';
import 'vela_connection_coordinator.dart';

/// Independent real-local proxy card. Does not alter the approved globe hero.
class VelaCoreSettingsCard extends StatelessWidget {
  const VelaCoreSettingsCard({
    super.key, required this.controller, this.connection,
  });
  final VelaCoreController controller;
  final VelaConnectionCoordinator? connection;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final theme = VelaThemeRuntime.active;
      final systemManaged = connection?.proxy.active == true;
      final coordinatedBusy = connection?.busy == true;
      final canChange = !controller.busy && !controller.isListening &&
          !systemManaged && !coordinatedBusy;
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha:
              theme.dark ? .63 : .85),
          border: Border.all(color: theme.text.withValues(alpha: theme.dark ? .30 : .24)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.settings_ethernet_rounded, color: theme.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('Vela 网络服务',
              style: TextStyle(color: theme.text, fontSize: 17,
                fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          Text(
            controller.usingBundledCore
              ? '已内置经 SHA-256 校验的网络服务。'
                '本地直连测试配置会自动创建；无需自行下载内核。'
              : '未发现打包内核，可重新解压完整便携包，'
                '或手动选择可信来源的 mihomo.exe。',
            style: TextStyle(color: theme.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 6),
          Text(
            '没有订阅或远程服务器时，只能进行本地直连测试，'
            '不能实现连接其他国家的网络。',
            style: TextStyle(color: theme.muted, fontSize: 12),
          ),
          const SizedBox(height: 15),
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (!controller.usingBundledCore)
            OutlinedButton.icon(
              key: const ValueKey('choose_core'),
              onPressed: canChange && controller.supported ? () async {
                try {
                  final file = await openFile(acceptedTypeGroups: [
                    const XTypeGroup(label:'mihomo.exe', extensions:['exe']),
                  ]);
                  if (file != null) {
                    await controller.chooseBinary(file.path);
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('无法打开内核文件选择窗口'),
                    ));
                  }
                }
              } : null,
              icon: const Icon(Icons.memory_rounded, size: 17),
              label: Text(controller.hasCore ? '已选择内核 ✓' : '选择 mihomo.exe'),
            ),

          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('reset_direct_profile'),
            onPressed: canChange && controller.supported
                ? controller.useLocalDirectProfile : null,
            icon: const Icon(Icons.settings_backup_restore_rounded, size: 17),
            label: const Text('恢复本地直连测试'),
          ),
          if (controller.directTestProfile) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '当前模式：仅本机直连测试（无远程节点）',
              style: TextStyle(color: theme.muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 14),
          Text(controller.supported ? controller.phaseLabel
              : '当前平台不支持此 Windows 内核功能',
              style: TextStyle(color: theme.text,
                fontWeight: FontWeight.w600)),
          if (controller.hasConfig) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('本地地址：${controller.localAddress}',
              style: TextStyle(color: theme.muted, fontSize: 12)),
          ),
          if (controller.error != null) Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(controller.error!,
              style: const TextStyle(color: Color(0xFFE78986), fontSize: 12)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(
              key: const ValueKey('real_core_toggle'),
              onPressed: !controller.supported || controller.busy ||
                  coordinatedBusy ? null : () {
                if (systemManaged) {
                  connection!.disconnect();
                } else if (controller.isListening) {
                  controller.stop();
                } else {
                  controller.start();
                }
              },
              icon: Icon(controller.isListening
                  ? Icons.stop_circle_outlined : Icons.play_arrow_rounded),
              label: Text(systemManaged
                  ? '安全断开并恢复 Windows 代理'
                  : controller.isListening ? '停止本地代理' : '启动本地代理'),
            )),
          ]),
          if (controller.isListening && !controller.directTestProfile) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('real_remote_probe'),
              onPressed: controller.probing ? null : () {
                controller.verifyRemote();
              },
              icon: const Icon(Icons.network_check_rounded),
              label: Text(controller.probing ? '正在验证线路…'
                  : '验证真实外网连接'),
            ),
            const SizedBox(height: 6),
            Text(controller.remoteVerified
                ? '外网 HTTPS 代理验证成功（仅限当前测试地址）'
                : '尚未验证线路连通性',
              style: TextStyle(
                color: controller.remoteVerified ? theme.accent : theme.muted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '节点与订阅请在「配置」页管理，测速和切换在「代理」页进行。'
            'Windows 系统代理由主界面的连接操作统一协调。',
            style: TextStyle(fontSize: 11, height: 1.55, color: theme.muted),
          ),
        ]),
      )));
    },
  );
}
