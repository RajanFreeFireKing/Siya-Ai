import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// "Siya Ai" gradient title + sparkle + neeche ka glowing arc.
class SiyaTitle extends StatelessWidget {
  const SiyaTitle({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final fs = width * 0.108;
    return SizedBox(
      width: width * 0.5,
      height: width * 0.2,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _UnderArcPainter()),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => const LinearGradient(
              colors: [SiyaColors.cyanSoft, Color(0xFF6FA8FF), SiyaColors.violet],
              stops: [0.0, 0.5, 1.0],
            ).createShader(r),
            child: Text(
              'Siya Ai',
              maxLines: 1,
              style: TextStyle(
                fontSize: fs,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(color: SiyaColors.cyan.withOpacity(0.55), blurRadius: 14),
                ],
              ),
            ),
          ),
          Positioned(
            right: width * 0.006,
            top: width * 0.012,
            child: SizedBox(
              width: width * 0.05,
              height: width * 0.05,
              child: CustomPaint(painter: _SparklePainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnderArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.02, size.height * 0.93)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.80, size.width * 0.98, size.height * 0.93);
    final shader = const LinearGradient(
      colors: [Colors.transparent, SiyaColors.cyanSoft, SiyaColors.violet, Colors.transparent],
      stops: [0.0, 0.35, 0.7, 1.0],
    ).createShader(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final ang = i * math.pi / 4 - math.pi / 2;
      final rad = i.isEven ? r : r * 0.22;
      final p = Offset(c.dx + math.cos(ang) * rad, c.dy + math.sin(ang) * rad);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = SiyaColors.violet.withOpacity(0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFD9C8FF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
