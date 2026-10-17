import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Static hand-laid pigment grain, independent from animated clouds/routes.
/// No random shader, no timer and no per-frame allocation.
class VelaOilImpasto extends StatelessWidget {
  const VelaOilImpasto({super.key});
  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child:RepaintBoundary(child:CustomPaint(
      painter:VelaOilImpastoPainter(),child:SizedBox.expand())));
}

class VelaOilImpastoPainter extends CustomPainter {
  const VelaOilImpastoPainter();
  static double _noise(int x,int y,int salt) {
    final value=(x*73856093 ^ y*19349663 ^ salt*83492791) & 0x7fffffff;
    return value/2147483647.0;
  }
  @override
  void paint(Canvas canvas,Size size) {
    if (size.isEmpty) return;
    final area=Rect.fromLTWH(0,0,size.width,size.height);
    canvas.save();canvas.clipRect(area);
    final p=Paint()..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final cols=(size.width/27).ceil();
    final rows=(size.height/19).ceil();
    for(var y=0;y<rows;y++) {
      for(var x=0;x<cols;x++) {
        final a=_noise(x,y,13), b=_noise(x,y,29);
        final start=Offset(x*27+a*13,y*19+b*7);
        final angle=(a-.5)*1.0;
        final length=5+_noise(x,y,7)*13;
        p.color=((x+y)%3==0 ? const Color(0xFFFFF8E1)
          :const Color(0xFF6C665B)).withValues(alpha:.07);
        p.strokeWidth=1.1+_noise(x,y,47)*2.0;
        canvas.drawLine(start,start+Offset(math.cos(angle)*length,
          math.sin(angle)*length*.43),p);
      }
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant VelaOilImpastoPainter old)=>false;
}
