import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Center wali glowing orb: concentric rings + wavy 8-lobe ribbon + particles.
/// [time] 0..1 repeat hota hai, [level] 0..1 (idle -> active) se ribbon ka size/glow badhta hai.
class OrbPainter extends CustomPainter {
  OrbPainter({required this.time, required this.level})
      : super(repaint: Listenable.merge([time, level]));

  final Animation<double> time;
  final ValueListenable<double> level;

  static final List<_Dot> _dots = _makeDots();

  static List<_Dot> _makeDots() {
    final r = math.Random(7);
    return List.generate(
      140,
      (i) => _Dot(
        angle: r.nextDouble() * math.pi * 2,
        radius: 0.34 + r.nextDouble() * 0.72,
        size: 0.6 + r.nextDouble() * (i < 30 ? 2.4 : 1.2),
        phase: r.nextDouble() * math.pi * 2,
        bright: i < 30,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = size.width / 2;
    final t = time.value * math.pi * 2;
    final lv = level.value;

    _drawDust(canvas, c, R, t, lv);
    _drawRings(canvas, c, R, t);
    _drawCore(canvas, c, R, t, lv);
    _drawRibbons(canvas, c, R, t, lv);
    _drawSparks(canvas, c, R, t);
  }

  // ── thin gradient rings + thick arcs ─────────────────────────
  void _drawRings(Canvas canvas, Offset c, double R, double t) {
    final rings = <List<double>>[
      // radiusFraction, strokeWidth, alpha, rotationSpeed
      [0.985, 1.2, 0.55, 1],
      [0.955, 3.2, 0.85, -1],
      [0.925, 1.0, 0.40, 2],
      [0.885, 1.0, 0.35, -2],
      [0.845, 0.8, 0.30, 1],
      [0.79, 0.8, 0.22, -1],
    ];
    for (final ring in rings) {
      final r = R * ring[0];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring[1]
        ..shader = ui.Gradient.sweep(
          c,
          [
            SiyaColors.cyanSoft.withOpacity(ring[2]),
            SiyaColors.blue.withOpacity(ring[2] * 0.6),
            SiyaColors.purple.withOpacity(ring[2]),
            SiyaColors.blue.withOpacity(ring[2] * 0.6),
            SiyaColors.cyanSoft.withOpacity(ring[2]),
          ],
          [0.0, 0.25, 0.5, 0.75, 1.0],
          TileMode.clamp,
          0,
          math.pi * 2,
          _rot(c, t * ring[3] * 0.25),
        );
      canvas.drawCircle(c, r, paint);
      if (ring[1] > 3) {
        // glow for the thick ring
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring[1] * 2.6
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
            ..shader = paint.shader
            ..color = Colors.white.withOpacity(0.25),
        );
      }
    }

    // bright arcs (cyan left-top, purple right-top) like the design
    _arc(canvas, c, R * 0.90, -math.pi * 0.98 + t * 0.05, math.pi * 0.62,
        SiyaColors.cyanSoft, 3.6);
    _arc(canvas, c, R * 0.81, -math.pi * 0.42 + t * -0.04, math.pi * 0.48,
        SiyaColors.violet, 3.2);
    _arc(canvas, c, R * 0.865, math.pi * 0.10 + t * 0.03, math.pi * 0.55,
        SiyaColors.blue, 2.6);
  }

  void _arc(Canvas canvas, Offset c, double r, double start, double sweep,
      Color color, double width) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width * 2.8
        ..color = color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..shader = ui.Gradient.linear(
          Offset(c.dx - r, c.dy),
          Offset(c.dx + r, c.dy),
          [color.withOpacity(0.1), color, color.withOpacity(0.1)],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  // ── dark hole + soft haze ────────────────────────────────────
  void _drawCore(Canvas canvas, Offset c, double R, double t, double lv) {
    final haze = Paint()
      ..shader = ui.Gradient.radial(
        c,
        R * 0.78,
        [
          Colors.black,
          const Color(0xFF020A14).withOpacity(0.0),
          SiyaColors.blue.withOpacity(0.10 + 0.10 * lv),
          Colors.transparent,
        ],
        [0.0, 0.42, 0.72, 1.0],
      );
    canvas.drawCircle(c, R * 0.78, haze);
  }

  // ── wavy ribbon (8 lobes) ────────────────────────────────────
  void _drawRibbons(Canvas canvas, Offset c, double R, double t, double lv) {
    const lobes = 8;
    final amp = 0.13 + 0.10 * lv;
    final scale = 1.0 + 0.04 * lv;
    final curves = <List<double>>[
      // base, ampMul, phaseOffset, width, alpha
      [0.66, 1.00, 0.0, 2.6, 1.0],
      [0.64, 0.85, 0.9, 2.2, 0.9],
      [0.68, 1.15, 1.9, 2.0, 0.8],
      [0.62, 0.70, 2.7, 1.6, 0.7],
    ];
    final shader = ui.Gradient.sweep(
      c,
      [
        SiyaColors.cyanSoft,
        const Color(0xFFBFEFFF),
        SiyaColors.violet,
        SiyaColors.cyanSoft,
        const Color(0xFFE6F8FF),
        SiyaColors.purple,
        SiyaColors.cyanSoft,
      ],
      [0.0, 0.16, 0.34, 0.5, 0.68, 0.84, 1.0],
      TileMode.clamp,
      0,
      math.pi * 2,
      _rot(c, t * 0.5),
    );

    for (final cv in curves) {
      final path = Path();
      final base = R * cv[0] * scale;
      const steps = 220;
      for (int i = 0; i <= steps; i++) {
        final th = i / steps * math.pi * 2;
        final wobble = math.sin(lobes * th + t * 2 + cv[2]) * amp * cv[1] +
            math.sin((lobes ~/ 2) * th - t * 3 + cv[2]) * 0.03 * (0.4 + lv);
        final r = base * (1 + wobble);
        final p = Offset(c.dx + math.cos(th) * r, c.dy + math.sin(th) * r);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();

      // soft glow
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cv[3] * 4.5
          ..shader = shader
          ..color = Colors.white.withOpacity(0.35 * cv[4])
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      // core line
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cv[3]
          ..strokeJoin = StrokeJoin.round
          ..shader = shader
          ..color = Colors.white.withOpacity(cv[4]),
      );
    }
  }

  // ── fine dust between the rings ──────────────────────────────
  void _drawDust(Canvas canvas, Offset c, double R, double t, double lv) {
    final p = Paint();
    for (final d in _dots) {
      if (d.bright) continue;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 6 + d.phase));
      final a = d.angle + t * 0.05;
      final r = R * d.radius * 0.72;
      p.color = SiyaColors.cyanSoft.withOpacity(0.10 + 0.32 * tw * (0.5 + lv));
      canvas.drawCircle(Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r), d.size * 0.6, p);
    }
  }

  // ── bright sparks around the outer rings ─────────────────────
  void _drawSparks(Canvas canvas, Offset c, double R, double t) {
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final core = Paint();
    for (final d in _dots) {
      if (!d.bright) continue;
      final tw = 0.5 + 0.5 * math.sin(t * 5 + d.phase);
      final a = d.angle - t * 0.03;
      final r = R * (0.62 + d.radius * 0.42);
      final o = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      glow.color = SiyaColors.cyanSoft.withOpacity(0.45 * tw);
      core.color = Colors.white.withOpacity(0.55 + 0.45 * tw);
      canvas.drawCircle(o, d.size * 2.2, glow);
      canvas.drawCircle(o, d.size * 0.7, core);
    }
  }

  @override
  bool shouldRepaint(covariant OrbPainter old) => false;
}

class _Dot {
  const _Dot({
    required this.angle,
    required this.radius,
    required this.size,
    required this.phase,
    required this.bright,
  });
  final double angle;
  final double radius;
  final double size;
  final double phase;
  final bool bright;
}

/// Sweep gradient ko circle ke center par rotate karne ke liye matrix.
Float64List _rot(Offset c, double angle) {
  final m = Matrix4.translationValues(c.dx, c.dy, 0) *
      Matrix4.rotationZ(angle) *
      Matrix4.translationValues(-c.dx, -c.dy, 0);
  return Float64List.fromList(m.storage);
}
