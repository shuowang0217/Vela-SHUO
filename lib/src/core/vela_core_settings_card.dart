import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../theme/vela_palettes.dart';
import 'vela_core_controller.dart';

/// Independent real-local proxy card. Does not alter the approved globe hero.
class VelaCoreSettingsCard extends StatelessWidget {
  const VelaCoreSettingsCard({super.key, required this.controller});
  final VelaCoreController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final theme = VelaThemeRuntime.active;
      final canChange = !controller.busy && !controller.isListening;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha: .94),
          border: Border.all(color: theme.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.settings_ethernet_rounded, color: theme.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('本地代理内核 · v0.2 Alpha',
              style: TextStyle(color: theme.text, fontSize: 17,
                fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          Text(
            '使用你自行提供的 sing-box.exe 与本地 JSON 配置。'
            '程序不会上传配置、自动安装内核或修改 Windows 系统代理。',
            style: TextStyle(color: theme.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 15),
          Wrap(spacing: 10, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const ValueKey('choose_core'),
              onPressed: canChange && controller.supported ? () async {
                try {
                  final file = await openFile(acceptedTypeGroups: [
                    const XTypeGroup(label:'sing-box.exe', extensions:['exe']),
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
              label: Text(controller.hasCore ? '已选择内核 ✓' : '选择 sing-box.exe'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('choose_json'),
              onPressed: canChange && controller.supported ? () async {
                try {
                  final file = await openFile(acceptedTypeGroups: [
                    const XTypeGroup(label:'JSON 配置', extensions:['json']),
                  ]);
                  if (file != null) {
                    await controller.chooseConfig(file.path);
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('无法打开配置文件选择窗口'),
                    ));
                  }
                }
              } : null,
              icon: const Icon(Icons.description_outlined, size: 17),
              label: Text(controller.hasConfig ? '配置已校验 ✓' : '选择 JSON 配置'),
            ),
          ]),
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
              onPressed: !controller.supported || controller.busy
                  ? null : () {
                if (controller.isListening) {
                  controller.stop();
                } else {
                  controller.start();
                }
              },
              icon: Icon(controller.isListening
                  ? Icons.stop_circle_outlined : Icons.play_arrow_rounded),
              label: Text(controller.isListening
                  ? '停止本地代理' : '启动本地代理'),
            )),
          ]),
          const SizedBox(height: 10),
          Text(
            '仅验证内核运行与 127.0.0.1 端口监听；这不等于远程节点可用。'
            '本预览版不接管浏览器或系统流量。'
            '如需测试，请在支持手动代理的程序中自行配置上述地址。',
            style: TextStyle(fontSize: 11, height: 1.55, color: theme.muted),
          ),
        ]),
      );
    },
  );
}
