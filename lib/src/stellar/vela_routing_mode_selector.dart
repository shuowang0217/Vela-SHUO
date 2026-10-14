import 'package:flutter/material.dart';

import '../network/vela_routing_mode.dart';
import '../theme/vela_palettes.dart';
import 'stellar_design.dart';

/// Only native-acknowledged modes are ever marked as selected.
/// All three actions invoke the Go core's updateConfig RPC.
class VelaRoutingModeSelector extends StatelessWidget {
  const VelaRoutingModeSelector({
    super.key, required this.controller,
    required this.activeProfileId, this.locked = false,
  });

  final VelaRoutingModeController controller;
  final String? activeProfileId;
  final bool locked;

  Future<void> _change(BuildContext context, VelaRoutingMode mode) async {
    if (locked || controller.busy || !controller.backend.imported) return;
    final ok = await controller.setMode(mode, activeProfileId);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(controller.error ?? '航线模式切换失败，仍使用原模式'),
      ));
    } else if (controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final t = VelaThemeRuntime.active;
      final enabled = !locked && !controller.busy &&
          controller.backend.imported;
      return StellarPanel(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.alt_route_rounded, color: t.accent, size: 21),
            const SizedBox(width: 9),
            Expanded(child: Text('航线模式',
                style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w700, color: t.text))),
            if (controller.busy)
              const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            if (!controller.busy)
              StellarLabel(controller.backend.imported
                  ? '实际路由已接入核心' : '请先导入机场'),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final mode in VelaRoutingMode.values)
              ChoiceChip(
                key: ValueKey('routing_mode_${mode.wire}'),
                label: Text(mode.label),
                avatar: Icon(switch (mode) {
                  VelaRoutingMode.rule => Icons.rule_folder_outlined,
                  VelaRoutingMode.global => Icons.public_rounded,
                  VelaRoutingMode.direct => Icons.travel_explore_rounded,
                }, size: 18),
                selected: controller.current == mode,
                onSelected: enabled ? (_) => _change(context, mode) : null,
              ),
          ]),
          const SizedBox(height: 9),
          StellarLabel(controller.backend.imported
              ? controller.current.description
              : '添加机场后可选规则、全局或直连'),
          if (controller.error != null) ...[
            const SizedBox(height: 7),
            Text(controller.error!, style: TextStyle(
                color: t.accent, fontSize: 12)),
          ],
        ]),
      );
    },
  );
}
