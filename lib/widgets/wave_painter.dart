import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Efficient vector waveform painted into a single canvas.
class SiyaWavePainter extends CustomPainter {
  SiyaWavePainter({required this.time, required this.level, required this.active})
      : super(repaint: Listenable.merge([time, level]));

  final Animation<double> time;
  final ValueListenable<double> level;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cy = size.height / 2;
    const count = 45;
    final step = size.width / count;
    final barWidth = math.max(2.0, step * .4);
    final maxHeight = size.height * .88;
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final core = Paint();
    final phase = time.value * math.pi * 2 * (active ? 12 : 4);
    for (int i = 0; i < count; i++) {
      final dist = ((i - (count - 1) / 2).abs()) / ((count - 1) / 2);
      final envelope = math.pow(1 - dist, .72).toDouble();
      final rhythm = .35 + .65 * (.5 + .5 * math.sin(i * 1.7 + phase));
      final energy = active ? .42 + .58 * level.value : .47;
      final h = math.max(3.5, maxHeight * envelope * rhythm * energy);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(step * (i + .5), cy), width: barWidth, height: h),
        Radius.circular(barWidth),
      );
      final t = (1 - dist).clamp(0.0, 1.0);
      final color = Color.lerp(const Color(0xFFFF0060), const Color(0xFFB50020), t)!;
      glow.color = color.withOpacity(.48);
      core.color = color;
      canvas.drawRRect(rect, glow);
      canvas.drawRRect(rect, core);
    }
    final dotPaint = Paint()..color = const Color(0xFFE90049);
    canvas.drawCircle(Offset(size.width * .018, cy), 3.4, dotPaint);
    canvas.drawCircle(Offset(size.width * .982, cy), 3.4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant SiyaWavePainter oldDelegate) => oldDelegate.active != active;
}
