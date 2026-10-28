import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Efficient vector waveform painted into a single canvas.
/// Stays calm and flat when user is silent or mic is off,
/// and dynamically animates to speech amplitude with theme color.
class SiyaWavePainter extends CustomPainter {
  SiyaWavePainter({
    required this.time,
    required this.level,
    required this.active,
    this.primaryColor = const Color(0xFFE6004C),
  }) : super(repaint: Listenable.merge([time, level]));

  final Animation<double> time;
  final ValueListenable<double> level;
  final bool active;
  final Color primaryColor;

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

    // When mic is off or voice amplitude is silent/quiet, do NOT vibrate!
    final isSpeaking = active && level.value > 0.04;
    final phase = isSpeaking ? time.value * math.pi * 2 * 12 : 0.0;

    for (int i = 0; i < count; i++) {
      final dist = ((i - (count - 1) / 2).abs()) / ((count - 1) / 2);
      final envelope = math.pow(1 - dist, .72).toDouble();

      double h;
      if (isSpeaking) {
        final rhythm = .35 + .65 * (.5 + .5 * math.sin(i * 1.7 + phase));
        final energy = .35 + .65 * level.value;
        h = math.max(3.5, maxHeight * envelope * rhythm * energy);
      } else {
        // Calm flat baseline when user is silent or mic is off
        h = 3.5;
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(step * (i + .5), cy), width: barWidth, height: h),
        Radius.circular(barWidth),
      );
      final t = (1 - dist).clamp(0.0, 1.0);
      final color = Color.lerp(
        primaryColor,
        Color.lerp(primaryColor, Colors.white, 0.4)!,
        t,
      )!;
      glow.color = color.withOpacity(isSpeaking ? .48 : .15);
      core.color = color.withOpacity(isSpeaking ? 1.0 : .55);
      canvas.drawRRect(rect, glow);
      canvas.drawRRect(rect, core);
    }
    final dotPaint = Paint()..color = primaryColor.withOpacity(isSpeaking ? 1.0 : 0.4);
    canvas.drawCircle(Offset(size.width * .018, cy), 3.4, dotPaint);
    canvas.drawCircle(Offset(size.width * .982, cy), 3.4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant SiyaWavePainter oldDelegate) =>
      oldDelegate.active != active || oldDelegate.primaryColor != primaryColor;
}
