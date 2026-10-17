import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Six sprites sampled from the approved Vela oil-paint reference image.
/// These are independent transparent layers, never baked into the map.
@immutable
class VelaOilCloudSpec {
  const VelaOilCloudSpec({required this.file, required this.bounds,
    required this.seed, required this.amplitude, required this.opacity});
  final String file;
  final Rect bounds;
  final double seed;
  final Offset amplitude;
  final double opacity;
  Offset position(double phase) {
    final angle = 2 * math.pi * (phase + seed);
    return Offset(math.sin(angle) * amplitude.dx,
        math.cos(angle) * amplitude.dy);
  }
}

class VelaOilScene extends StatefulWidget {
  const VelaOilScene({super.key});
  static const referenceWidth = 1672.0;
  static const referenceHeight = 941.0;
  static const animationSeconds = 132;
  // Historical preview asset kept for backward compatibility, NOT displayed.
  static const backgroundAsset = 'assets/oil/oil_map_clean.webp';

  static const clouds = <VelaOilCloudSpec>[
    VelaOilCloudSpec(file:'cloud_beijing',bounds:Rect.fromLTWH(218,165,444,211),
      seed:.03,amplitude:Offset(49,12),opacity:.96),
    VelaOilCloudSpec(file:'cloud_north',bounds:Rect.fromLTWH(626,16,396,214),
      seed:.19,amplitude:Offset(53,16),opacity:.94),
    VelaOilCloudSpec(file:'cloud_east',bounds:Rect.fromLTWH(1149,204,523,280),
      seed:.35,amplitude:Offset(57,18),opacity:.97),
    VelaOilCloudSpec(file:'cloud_southwest',bounds:Rect.fromLTWH(158,486,428,230),
      seed:.55,amplitude:Offset(45,13),opacity:.95),
    VelaOilCloudSpec(file:'cloud_equator',bounds:Rect.fromLTWH(734,496,543,302),
      seed:.72,amplitude:Offset(62,18),opacity:.96),
    VelaOilCloudSpec(file:'cloud_southeast',bounds:Rect.fromLTWH(1251,692,421,180),
      seed:.88,amplitude:Offset(43,10),opacity:.94),
  ];
  @override
  State<VelaOilScene> createState() => _VelaOilSceneState();
}

class _VelaOilSceneState extends State<VelaOilScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _wind;
  bool _backgrounded=false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wind=AnimationController(vsync:this,
      duration:const Duration(seconds:VelaOilScene.animationSeconds));
  }
  void _syncWind() {
    final reduced=MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final testing=WidgetsBinding.instance.runtimeType.toString()
      .contains('TestWidgetsFlutterBinding');
    if (reduced || testing || _backgrounded) {
      _wind.stop();
    } else if (!_wind.isAnimating) {
      _wind.repeat();
    }
  }
  @override
  void didChangeDependencies() {super.didChangeDependencies();_syncWind();}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded=state!=AppLifecycleState.resumed;_syncWind();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);_wind.dispose();super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder:(context,c) {
    if (!c.hasBoundedWidth || !c.hasBoundedHeight ||
        c.maxWidth<=0 || c.maxHeight<=0) {
      return const SizedBox.shrink();
    }
    final scale=math.max(c.maxWidth/VelaOilScene.referenceWidth,
        c.maxHeight/VelaOilScene.referenceHeight);
    final dx=(c.maxWidth-VelaOilScene.referenceWidth*scale)/2;
    final dy=(c.maxHeight-VelaOilScene.referenceHeight*scale)/2;
    return IgnorePointer(child:ClipRect(child:RepaintBoundary(
      child:AnimatedBuilder(animation:_wind,builder:(context,_) {
        return Stack(fit:StackFit.expand,clipBehavior:Clip.hardEdge,children:[
          for (final cloud in VelaOilScene.clouds)
            Positioned(
              left:dx+cloud.bounds.left*scale,
              top:dy+cloud.bounds.top*scale,
              width:cloud.bounds.width*scale,
              height:cloud.bounds.height*scale,
              child:Transform.translate(
                offset:cloud.position(_wind.value)*scale,
                child:Opacity(opacity:cloud.opacity,
                  child:RepaintBoundary(child:Image.asset(
                    'assets/oil/clouds/${cloud.file}.png',
                    fit:BoxFit.fill,filterQuality:FilterQuality.medium,
                    gaplessPlayback:true)),
                ),
              ),
            ),
        ]);
      }),
    )));
  });
}
