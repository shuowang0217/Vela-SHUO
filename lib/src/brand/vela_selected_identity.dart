import 'package:flutter/material.dart';

/// The ONLY approved Vela branding. These are bitmap extracts of the user's
/// selected blue/gold palette-knife sail and painted handwritten wordmark.
/// They are not procedurally reconstructed or typeface substitutions.
const velaSelectedIconAsset = 'assets/brand/vela_selected_icon.png';
const velaSelectedWordmarkAsset = 'assets/brand/vela_selected_wordmark.png';

class VelaSelectedIcon extends StatelessWidget {
  const VelaSelectedIcon({super.key, this.size = 42});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Vela 蓝金帆船油画图标',
    child: Image.asset(velaSelectedIconAsset, width: size, height: size,
      filterQuality: FilterQuality.high, fit: BoxFit.contain,
      gaplessPlayback: true),
  );
}

class VelaSelectedWordmark extends StatelessWidget {
  const VelaSelectedWordmark({super.key, this.width = 204,
    this.height = 94});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'VELA 手写油画标志',
    child: Image.asset(velaSelectedWordmarkAsset, width: width,
      height: height, filterQuality: FilterQuality.high,
      fit: BoxFit.contain, gaplessPlayback: true),
  );
}
