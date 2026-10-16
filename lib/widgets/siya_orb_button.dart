import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Neeche ka bada glossy orb (design jaisa). Tap par mic start / stop.
/// Halo + glossy gola static paint hai; saans = Transform.scale, listening mein ripple rings.
class SiyaOrbButton extends StatefulWidget {
  const SiyaOrbButton({
    super.key,
    required this.size,
    required this.time,
    required this.level,
    required this.state,
    required this.onTap,
  });

  final double size; // halo ka poora size
  final Animation<double> time;
  final ValueListenable<double> level;
  final String state; // idle | waiting | listening | processing | speaking
  final VoidCallback onTap;

  @override
  State<SiyaOrbButton> createState() => _SiyaOrbButtonState();
}

class _SiyaOrbButtonState extends State<SiyaOrbButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.state != 'idle';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _RipplePainter(time: widget.time, level: widget.level)),
                  ),
                ),
              AnimatedBuilder(
                animation: Listenable.merge([widget.time, widget.level]),
                builder: (_, child) {
                  final b = 0.5 + 0.5 * math.sin(widget.time.value * math.pi * 2 * 4);
                  final s = 1.0 + (active ? 0.025 + 0.05 * widget.level.value : 0.018) * b;
                  return Transform.scale(scale: s, child: child);
                },
                child: RepaintBoundary(
                  child: CustomPaint(size: Size.square(widget.size), painter: const _OrbPainter()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = size.width / 2;
    // halo (do soft safed ring)
    canvas.drawCircle(c, R, Paint()..color = Colors.white.withOpacity(0.28));
    canvas.drawCircle(c, R, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.55));
    canvas.drawCircle(c, R * 0.86, Paint()..color = Colors.white.withOpacity(0.30));

    // glossy gola
    final r = R * 0.70;
    final body = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.45, 0.55),
          radius: 1.25,
          colors: [Color(0xFFFF8A3D), Color(0xFFFF4FA3), Color(0xFFC13BFF), Color(0xFF8E2DE2)],
          stops: [0.0, 0.38, 0.72, 1.0],
        ).createShader(body),
    );
    // upar ka halka safed chamak
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, -0.75),
          radius: 0.9,
          colors: [Colors.white.withOpacity(0.55), Colors.white.withOpacity(0)],
        ).createShader(body),
    );
    // beech ka safed glossy hissa
    final blob = Rect.fromCenter(center: Offset(c.dx - r * 0.05, c.dy + r * 0.05), width: r * 0.95, height: r * 0.95);
    canvas.drawOval(
      blob,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.97), Colors.white.withOpacity(0.55), Colors.white.withOpacity(0)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(blob),
    );
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.7));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.time, required this.level}) : super(repaint: Listenable.merge([time, level]));

  final Animation<double> time;
  final ValueListenable<double> level;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final ph = (time.value * 4 + i / 3) % 1.0; // 4 baar / loop
      canvas.drawCircle(
        c,
        R * (0.70 + ph * 0.36),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1 - ph) + 0.4
          ..color = SiyaLight.pink.withOpacity((1 - ph) * (0.35 + 0.35 * level.value)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
