import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vela 1.8 oil-paint artwork test. This widget is strictly a backdrop;
/// Flutter routes, the native proxy/VPN and interactive controls stay separate.
/// The image is deliberately drawn at the reference's 1672x941 aspect ratio.
@immutable
class VelaOilCloudSpec {
  const VelaOilCloudSpec({
    required this.file,
    required this.bounds,
    required this.seed,
    required this.amplitude,
    required this.opacity,
  });

  final String file;
  final Rect bounds;
  final double seed;
  final Offset amplitude;
  final double opacity;

  /// Sinusoidal travel is continuous when the animation repeats, not a jump
  /// from the end of one image to the start of another.
  Offset position(double phase) {
    final angle = (phase + seed) * 2 * math.pi;
    return Offset(math.sin(angle) * amplitude.dx,
        math.cos(angle) * amplitude.dy);
  }
}

class VelaOilScene extends StatefulWidget {
  const VelaOilScene({super.key});

  static const referenceWidth = 1672.0;
  static const referenceHeight = 941.0;
  static const animationSeconds = 132;
  static const backgroundAsset = 'assets/oil/oil_map_clean.webp';

  /// Positions are referenced against the *actual approved screenshot*.
  /// This is a prototype extraction from its flattened layers.
  static const clouds = <VelaOilCloudSpec>[
    VelaOilCloudSpec(file: 'cloud_beijing',
      bounds: Rect.fromLTWH(218, 165, 444, 211),
      seed: .03, amplitude: Offset(16, 9), opacity: .30),
    VelaOilCloudSpec(file: 'cloud_north',
      bounds: Rect.fromLTWH(626, 16, 396, 214),
      seed: .19, amplitude: Offset(21, 9), opacity: .33),
    VelaOilCloudSpec(file: 'cloud_east',
      bounds: Rect.fromLTWH(1149, 204, 523, 280),
      seed: .35, amplitude: Offset(22, 13), opacity: .37),
    VelaOilCloudSpec(file: 'cloud_southwest',
      bounds: Rect.fromLTWH(158, 486, 428, 230),
      seed: .55, amplitude: Offset(28, 8), opacity: .34),
    VelaOilCloudSpec(file: 'cloud_equator',
      bounds: Rect.fromLTWH(734, 496, 543, 302),
      seed: .72, amplitude: Offset(26, 10), opacity: .35),
    VelaOilCloudSpec(file: 'cloud_southeast',
      bounds: Rect.fromLTWH(1251, 692, 421, 180),
      seed: .88, amplitude: Offset(19, 7), opacity: .30),
  ];

  @override
  State<VelaOilScene> createState() => _VelaOilSceneState();
}

class _VelaOilSceneState extends State<VelaOilScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _wind;
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wind = AnimationController(vsync: this,
        duration: const Duration(seconds: VelaOilScene.animationSeconds));
  }

  void _syncWind() {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final inTest = WidgetsBinding.instance.runtimeType.toString()
        .contains('TestWidgetsFlutterBinding');
    if (reduceMotion || _backgrounded || inTest) {
      _wind.stop();
    } else if (!_wind.isAnimating) {
      _wind.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWind();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    _syncWind();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight ||
          constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
        return const SizedBox.shrink();
      }
      final scale = math.max(
          constraints.maxWidth / VelaOilScene.referenceWidth,
          constraints.maxHeight / VelaOilScene.referenceHeight);
      final viewportWidth = VelaOilScene.referenceWidth * scale;
      final viewportHeight = VelaOilScene.referenceHeight * scale;
      return IgnorePointer(child: ClipRect(child: OverflowBox(
        alignment: Alignment.center,
        minWidth: viewportWidth, maxWidth: viewportWidth,
        minHeight: viewportHeight, maxHeight: viewportHeight,
        child: SizedBox(width: viewportWidth, height: viewportHeight,
          child: FittedBox(fit: BoxFit.fill, child: SizedBox(
            width: VelaOilScene.referenceWidth,
            height: VelaOilScene.referenceHeight,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(VelaOilScene.backgroundAsset,
                fit: BoxFit.fill, filterQuality: FilterQuality.medium),
              // Real alpha PNG sprites, not shader masks. Repaint isolated.
              AnimatedBuilder(animation: _wind, builder: (context, _) {
                return Stack(children: [
                  for (final cloud in VelaOilScene.clouds)
                    Positioned(left: cloud.bounds.left, top: cloud.bounds.top,
                      width: cloud.bounds.width, height: cloud.bounds.height,
                      child: Transform.translate(
                        offset: cloud.position(_wind.value),
                        child: Opacity(opacity: cloud.opacity,
                          child: RepaintBoundary(child: Image.asset(
                            'assets/oil/clouds/${cloud.file}.png',
                            fit: BoxFit.fill, gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          )),
                        ),
                      ),
                    ),
                ]);
              }),
            ]),
          )),
        ),
      )));
    },
  );
}