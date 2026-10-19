import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/vela_palettes.dart';

/// One floating, translucent notice above the app, rather than a bottom
/// Material SnackBar. Does not affect proxy/VPN state.
class VelaGlassToast {
  VelaGlassToast._();

  static OverlayEntry? _active;
  static Timer? _expiry;

  static void show(BuildContext context, String message) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    dismiss();
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (context) => Positioned(
      left: 0, right: 0, top: 0,
      child: SafeArea(bottom: false, child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _VelaGlassNotice(
              message: message, onDismiss: dismiss),
          ),
        ),
      )),
    ));
    _active = entry;
    overlay.insert(entry);
    _expiry = Timer(const Duration(milliseconds: 3500), () {
      if (identical(_active, entry)) dismiss();
    });
  }

  static void dismiss() {
    _expiry?.cancel();
    _expiry = null;
    final entry = _active;
    _active = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }
}

class _VelaGlassNotice extends StatelessWidget {
  const _VelaGlassNotice({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // One palette-driven notice across all eight themes and both modes.
    final tokens = VelaThemeRuntime.active;
    final dark = tokens.dark;
    final ink = tokens.text;
    final tint = Color.lerp(tokens.surface, tokens.raised, .30)!;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('vela_glass_toast'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - t)), child: child),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(
              color: tokens.background.withValues(alpha: dark ? .44 : .24),
              blurRadius: 28, offset: const Offset(0, 9),
            )],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: dark ? .78 : .80),
                      tint.withValues(alpha: dark ? .59 : .65),
                    ],
                  ),
                  border: Border.all(
                    color: tokens.accent.withValues(alpha: dark ? .66 : .52),
                    width: 1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sailing_rounded,
                      color: tokens.accent, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(message,
                      style: TextStyle(color: ink, fontSize: 13.5,
                        fontWeight: FontWeight.w500, height: 1.35))),
                    const SizedBox(width: 8),
                    InkResponse(
                      onTap: onDismiss,
                      radius: 16,
                      child: Icon(Icons.close_rounded, size: 17,
                        color: tokens.muted),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
