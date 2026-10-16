import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Mic ke dono side ki equalizer bars (edge par purple dots -> mic ke paas cyan).
/// [leftSide] true ho to bars left side wali hoti hain (edge = left).
class WavePainter extends CustomPainter {
  WavePainter({required this.time, required this.level, required this.leftSide})
      : super(repaint: Listenable.merge([time, level]));

  final Animation<double> time;
  final ValueListenable<double> level;
  final bool leftSide;

  static const int _n = 42;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / _n;
    final barW = math.max(1.6, step * 0.42);
    final maxH = size.height;
    final t = time.value * math.pi * 2 * 16;
    final lv = level.value;
    final cy = size.height / 2;

    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    final core = Paint();

    for (int i = 0; i < _n; i++) {
      final u = i / (_n - 1); // 0 = outer edge, 1 = mic side
      final x = leftSide ? (i + 0.5) * step : size.width - (i + 0.5) * step;

      final env = math.pow(math.sin(math.pi * math.pow(u, 1.15)), 1.25).toDouble();
      final mod = 0.5 + 0.5 * math.sin(i * 2.3 + t * (0.8 + (i % 3) * 0.2));
      final drive = 0.38 + 0.62 * lv;
      final h = math.max(3.0, maxH * env * (0.22 + 0.78 * mod) * drive);

      final color = Color.lerp(SiyaColors.purple, SiyaColors.cyanSoft, math.pow(u, 0.8).toDouble())!;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: barW, height: h),
        Radius.circular(barW / 2),
      );
      glow.color = color.withOpacity(0.45);
      core.color = color;
      canvas.drawRRect(rect, glow);
      canvas.drawRRect(rect, core);
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter old) => old.leftSide != leftSide;
}
