import 'package:flutter/material.dart';

import '../theme.dart';

/// Naye design ka gradient background: upar-left orange, upar-right magenta, beech mein safed,
/// neeche-left orange, neeche-right pink/violet.
/// Ye STATIC hai (repaint nahi hota) isliye har phone par bilkul smooth rehta hai.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: CustomPaint(painter: _AuroraPainter(), size: Size.infinite),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter();

  void _blob(Canvas canvas, Size s, Offset c, double r, Color color, double alpha) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withOpacity(alpha), color.withOpacity(alpha * 0.45), color.withOpacity(0)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawRect(Offset.zero & s, Paint()..color = Colors.white);
    // upar
    _blob(canvas, s, Offset(w * 0.05, h * 0.02), w * 0.80, SiyaLight.orange, 0.95);
    _blob(canvas, s, Offset(w * 0.98, h * 0.00), w * 0.85, SiyaLight.magenta, 0.95);
    _blob(canvas, s, Offset(w * 0.48, h * 0.02), w * 0.45, const Color(0xFFFFC4E8), 0.55);
    // neeche
    _blob(canvas, s, Offset(w * 0.02, h * 1.00), w * 0.85, SiyaLight.orange, 0.95);
    _blob(canvas, s, Offset(w * 0.98, h * 1.00), w * 0.90, SiyaLight.magenta, 0.95);
    _blob(canvas, s, Offset(w * 0.55, h * 1.02), w * 0.55, SiyaLight.violet, 0.55);
    // beech ka safed halka
    final mid = Rect.fromLTWH(0, h * 0.18, w, h * 0.62);
    canvas.drawRect(
      mid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(0.55), Colors.white.withOpacity(0.55), Colors.white.withOpacity(0)],
          stops: const [0.0, 0.25, 0.75, 1.0],
        ).createShader(mid),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
