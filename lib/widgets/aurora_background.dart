import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared light silk Aurora background used by sub screens.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SiyaTheme.accent,
      builder: (context, accent, _) {
        return RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(accent.withOpacity(.04), const Color(0xFFFFF7FB)),
                  Colors.white,
                  Color.alphaBlend(accent.withOpacity(.06), const Color(0xFFFFF2F8)),
                ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
            child: CustomPaint(painter: _AuroraSilkPainter(accent: accent), size: Size.infinite),
          ),
        );
      },
    );
  }
}

class _AuroraSilkPainter extends CustomPainter {
  const _AuroraSilkPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final glows = <(Offset, double, Color)>[
      (Offset(size.width * 0.12, size.height * 0.10), size.width * 0.85, accent),
      (Offset(size.width * 0.95, size.height * 0.32), size.width * 0.75, Color.lerp(accent, const Color(0xFFFF4893), 0.5)!),
      (Offset(size.width * 0.40, size.height * 0.95), size.width * 0.90, accent),
    ];
    for (final (center, radius, color) in glows) {
      final glowRect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withOpacity(0.12), color.withOpacity(0.04), color.withOpacity(0)],
            stops: const [0, 0.58, 1],
          ).createShader(glowRect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraSilkPainter oldDelegate) => oldDelegate.accent != accent;
}
