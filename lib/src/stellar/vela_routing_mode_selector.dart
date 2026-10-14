import 'package:flutter/material.dart';

import '../network/vela_routing_mode.dart';
import '../theme/vela_palettes.dart';
import 'stellar_design.dart';

/// Compact main-dashboard route switcher. Highlight changes only after the
/// existing native-core controller confirms updateConfig, never optimistically.
class VelaRoutingModeSelector extends StatelessWidget {
  const VelaRoutingModeSelector({
    super.key,
    required this.controller,
    required this.activeProfileId,
    this.locked = false,
  });

  final VelaRoutingModeController controller;
  final String? activeProfileId;
  final bool locked;

  Future<void> _change(BuildContext context, VelaRoutingMode mode) async {
    if (locked || controller.busy || !controller.backend.imported ||
        controller.current == mode) {
      return;
    }
    final ok = await controller.setMode(mode, activeProfileId);
    if (!context.mounted) return;
    if (!ok || controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(controller.error ??
            '航线模式切换失败，仍使用原模式'),
      ));
    }
  }

  IconData _icon(VelaRoutingMode mode) => switch (mode) {
    VelaRoutingMode.rule => Icons.alt_route_rounded,
    VelaRoutingMode.global => Icons.public_rounded,
    VelaRoutingMode.direct => Icons.near_me_outlined,
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final t = VelaThemeRuntime.active;
      final enabled = !locked && !controller.busy &&
          controller.backend.imported;
      final label = controller.backend.imported
          ? controller.current.description : '导入机场后可选择分流方式';
      return StellarPanel(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.explore_outlined, color: t.accent, size: 21),
              const SizedBox(width: 8),
              Expanded(child: Text('航线模式',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: t.text))),
              if (controller.busy)
                const SizedBox(width: 15, height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text(controller.backend.imported ? '已同步' : '待配置',
                  style: TextStyle(fontSize: 11, color: t.muted)),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: t.surface.withValues(alpha: t.dark ? .24 : .38),
                border: Border.all(color: t.text.withValues(alpha: .12)),
              ),
              child: Row(children: [
                for (final mode in VelaRoutingMode.values)
                  Expanded(child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('routing_mode_${mode.wire}'),
                      borderRadius: BorderRadius.circular(11),
                      onTap: enabled ? () => _change(context, mode) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 170),
                        height: 39,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          color: controller.current == mode
                              ? t.accent.withValues(alpha: t.dark ? .29 : .23)
                              : Colors.transparent,
                          border: Border.all(
                            color: controller.current == mode
                                ? t.accent.withValues(alpha: .50)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_icon(mode), size: 16,
                              color: !enabled ? t.muted
                                : controller.current == mode
                                  ? t.accent : t.text),
                            const SizedBox(width: 5),
                            Flexible(child: Text(mode.label,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12,
                                fontWeight: controller.current == mode
                                    ? FontWeight.w700 : FontWeight.w500,
                                color: !enabled ? t.muted : t.text))),
                          ],
                        ),
                      ),
                    ),
                  )),
              ]),
            ),
            const SizedBox(height: 8),
            Text(controller.error ?? label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11,
                color: controller.error == null ? t.muted : t.accent)),
          ],
        ),
      );
    },
  );
}
