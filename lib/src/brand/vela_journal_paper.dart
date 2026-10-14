import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/vela_palettes.dart';

/// Every Vela palette uses this material vocabulary: irregular pen line,
/// real paper grain, watercolor stains, and subdued hand-drawn ornaments.
/// Palette changes tint the ink; they never change the product's identity.
class VelaJournalPaper extends StatelessWidget {
  const VelaJournalPaper({
    super.key, required this.child,
    this.padding=const EdgeInsets.all(18),
    this.radius=17, this.selected=false, this.hovered=false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool selected;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final t=VelaThemeRuntime.active;
    final borderRadius=BorderRadius.circular(radius);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 210),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: borderRadius,
        image: DecorationImage(
          image: AssetImage(t.dark
              ? 'assets/journal/paper_night.jpg'
              : 'assets/journal/paper_day.jpg'),
          fit: BoxFit.cover, opacity: .92,
        ),
        border: Border.all(
          color: selected || hovered ? t.accent : t.line,
          width: selected ? 1.6 : 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101D22)
              .withValues(alpha: t.dark ? .36 : .22),
            blurRadius: hovered || selected ? 20 : 12,
            offset: const Offset(2, 6),
          ),
        ],
      ),
      child: CustomPaint(
        painter: VelaJournalInkBorder(
          color: t.dark ? t.accentSoft : t.text,
          radius: radius, selected: selected || hovered),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A second, slightly irregular ink contour gives cards the physical-paper look.
class VelaJournalInkBorder extends CustomPainter {
  const VelaJournalInkBorder({required this.color,
    this.radius=17, this.selected=false});
  final Color color;
  final double radius;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    if(size.width<20||size.height<20)return;
    final pen=Paint()
      ..color=color.withValues(alpha: selected ? .53 : .32)
      ..style=PaintingStyle.stroke
      ..strokeWidth=.85
      ..strokeCap=StrokeCap.round;
    final rect=Rect.fromLTWH(3.5,3.5,size.width-7,size.height-7);
    final rr=RRect.fromRectAndRadius(rect,Radius.circular(radius-3));
    canvas.drawRRect(rr,pen);
    final wash=Paint()
      ..color=color.withValues(alpha: .075)
      ..style=PaintingStyle.stroke..strokeWidth=1.2;
    final line=Path()
      ..moveTo(20,7)..quadraticBezierTo(size.width*.42,5.5,
        size.width*.66,7.6)
      ..quadraticBezierTo(size.width*.82,9,size.width-19,7);
    canvas.drawPath(line,wash);
    canvas.drawLine(
      Offset(15,size.height-10),Offset(math.max(16,size.width*.24),
      size.height-11),wash);
    if(selected){
      canvas.drawLine(const Offset(11,20),const Offset(11,35),
          pen..strokeWidth=1.3);
    }
  }

  @override
  bool shouldRepaint(covariant VelaJournalInkBorder old)=>
    old.color!=color||old.radius!=radius||old.selected!=selected;
}

/// Tiny physical passport stamp, used only as noninteractive decoration.
class VelaPostmark extends StatelessWidget {
  const VelaPostmark({super.key,this.size=70});
  final double size;
  @override
  Widget build(BuildContext context) {
    final color=VelaThemeRuntime.active.muted;
    return IgnorePointer(child: SizedBox(width:size,height:size,
      child: CustomPaint(painter:_StampPainter(color))));
  }
}
class _StampPainter extends CustomPainter {
  const _StampPainter(this.ink);
  final Color ink;
  @override
  void paint(Canvas canvas, Size s) {
    final r=math.min(s.width,s.height)*.43;
    final c=Offset(s.width/2,s.height/2);
    final line=Paint()..color=ink.withValues(alpha:.33)
      ..style=PaintingStyle.stroke..strokeWidth=1;
    canvas.drawCircle(c,r,line);
    canvas.drawCircle(c,r*.81,line);
    canvas.save();canvas.translate(c.dx,c.dy);
    canvas.rotate(-.28);
    final tp=TextPainter(text:TextSpan(text:'VELA',
      style:TextStyle(fontFamily:'Georgia',fontSize:r*.36,
        fontWeight:FontWeight.bold,color:ink.withValues(alpha:.4))),
        textDirection:TextDirection.ltr)..layout();
    tp.paint(canvas,Offset(-tp.width/2,-tp.height/2));
    canvas.restore();
    for (var i=0;i<3;i++) {
      canvas.drawArc(Rect.fromLTWH(s.width*.09,s.height*(.47+i*.085),
        s.width*.75,s.height*.21),0,math.pi,false,line);
    }
  }
  @override bool shouldRepaint(covariant _StampPainter old)=>old.ink!=ink;
}

class VelaLighthouseSketch extends StatelessWidget{
  const VelaLighthouseSketch({super.key});
  @override Widget build(BuildContext context){
    final t=VelaThemeRuntime.active;
    return IgnorePointer(child:SizedBox(height:133,width:166,
      child:CustomPaint(painter:_LighthousePainter(t.text,t.accent,t.accentSoft))));
  }
}
class _LighthousePainter extends CustomPainter{
  const _LighthousePainter(this.ink,this.sea,this.gold);
  final Color ink,sea,gold;
  @override void paint(Canvas c,Size s){
    c.save();c.scale(s.width/166,s.height/133);
    final p=Paint()..color=ink.withValues(alpha:.65)
      ..style=PaintingStyle.stroke..strokeWidth=1.4
      ..strokeCap=StrokeCap.round;
    final coast=Path()..moveTo(8,117)
      ..quadraticBezierTo(37,100,60,111)
      ..quadraticBezierTo(91,86,130,110)
      ..lineTo(160,117);
    c.drawPath(coast,p);
    c.drawPath(Path()..moveTo(65,99)..lineTo(74,45)..lineTo(94,45)
      ..lineTo(104,101)..close(),Paint()..color=sea.withValues(alpha:.24));
    c.drawPath(Path()..moveTo(65,99)..lineTo(74,45)..lineTo(94,45)
      ..lineTo(104,101),p);
    c.drawLine(const Offset(71,50),const Offset(97,50),p);
    c.drawRect(const Rect.fromLTWH(75,31,18,14),p);
    c.drawLine(const Offset(69,30),const Offset(99,30),p);
    c.drawPath(Path()..moveTo(72,30)..lineTo(84,18)
      ..lineTo(96,30),p);
    c.drawRect(const Rect.fromLTWH(80,62,9,11),p);
    c.drawLine(const Offset(84,14),const Offset(84,20),p);
    c.drawPath(Path()..moveTo(48,45)..quadraticBezierTo(84,19,118,46),
      Paint()..color=gold.withValues(alpha:.31)
        ..style=PaintingStyle.stroke..strokeWidth=4);
    for(final pt in [const Offset(23,70),const Offset(134,57)]){
      c.drawPath(Path()..moveTo(pt.dx-8,pt.dy)
        ..quadraticBezierTo(pt.dx-3,pt.dy-5,pt.dx,pt.dy)
        ..quadraticBezierTo(pt.dx+3,pt.dy-5,pt.dx+8,pt.dy),p);
    }
    c.drawPath(Path()..moveTo(0,122)..quadraticBezierTo(50,115,83,125)
      ..quadraticBezierTo(120,118,164,124),Paint()
      ..color=sea.withValues(alpha:.62)
      ..strokeWidth=2..style=PaintingStyle.stroke);
    c.restore();
  }
  @override bool shouldRepaint(covariant _LighthousePainter old)=>
    old.ink!=ink||old.sea!=sea||old.gold!=gold;
}
