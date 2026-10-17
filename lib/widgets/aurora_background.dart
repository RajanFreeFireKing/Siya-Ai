import 'package:flutter/material.dart';

/// Shared deep-purple Aurora background used by every main screen.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF09051A), Color(0xFF16092E), Color(0xFF080414)],
              stops: [0.0, 0.52, 1.0],
            ),
          ),
          child: CustomPaint(painter: _AuroraGlowPainter(), size: Size.infinite),
        ),
      );
}

class _AuroraGlowPainter extends CustomPainter {
  const _AuroraGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final glows = <(Offset, double, Color)>[
      (Offset(size.width * 0.08, size.height * 0.08), size.width * 0.82, const Color(0xFF6030B0)),
      (Offset(size.width * 0.98, size.height * 0.28), size.width * 0.72, const Color(0xFF35166D)),
      (Offset(size.width * 0.45, size.height * 1.02), size.width * 0.95, const Color(0xFF442080)),
    ];
    for (final (center, radius, color) in glows) {
      final glowRect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withOpacity(0.25), color.withOpacity(0.08), color.withOpacity(0)],
            stops: const [0, 0.58, 1],
          ).createShader(glowRect),
      );
    }
    final sheen = Rect.fromLTWH(0, size.height * 0.24, size.width, size.height * 0.55);
    canvas.drawRect(sheen, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0x000F0724), Color(0x182D1555), Color(0x000F0724)],
    ).createShader(sheen));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
