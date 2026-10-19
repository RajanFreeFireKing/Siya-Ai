import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Reference-style hologram: soft pink central glow surrounded by orbiting pink particles.
class DotRing extends StatelessWidget {
  const DotRing({
    super.key,
    required this.size,
    required this.time,
    required this.level,
    required this.label,
  });

  final double size;
  final Animation<double> time; // 0..1 repeat
  final ValueListenable<double> level; // 0..1 awaaz / activity
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft pink center glow from the supplied design.
          AnimatedBuilder(
            animation: Listenable.merge([time, level]),
            builder: (_, child) {
              final breathe = 0.5 + 0.5 * math.sin(time.value * math.pi * 2 * 3);
              return Transform.scale(
                scale: 0.96 + breathe * 0.045 + level.value * 0.035,
                child: child,
              );
            },
            child: Container(
              width: size * 0.72,
              height: size * 0.72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xF5F42AA7), Color(0xBFF64DB8), Color(0x55FF9EDB), Color(0x00FFFFFF)],
                  stops: [0.0, 0.48, 0.78, 1.0],
                ),
              ),
            ),
          ),
          // dots
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _DotsPainter(time: time, level: level)),
            ),
          ),
          // text
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              label,
              key: ValueKey(label),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.092,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.2,
                shadows: const [Shadow(color: Color(0x33E0168F), blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot {
  const _Dot(this.angle, this.off, this.size, this.rot, this.breathe, this.phase, this.halo);
  final double angle; // shuruaati kon
  final double off; // ring se andar/bahar (R ka hissa)
  final double size; // R ka hissa
  final int rot; // ghoomne ki gati (poore chakkar / loop)
  final int breathe; // saans ki frequency (integer = loop seamless)
  final double phase;
  final bool halo;
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.time, required this.level}) : super(repaint: Listenable.merge([time, level]));

  final Animation<double> time;
  final ValueListenable<double> level;

  static const int _n = 240;
  static final List<_Dot> _dots = _make();

  static List<_Dot> _make() {
    final r = math.Random(11);
    return List.generate(_n, (i) {
      final big = i % 19 == 0;
      return _Dot(
        (i / _n) * math.pi * 2 + (r.nextDouble() - 0.5) * 0.09,
        (r.nextDouble() - 0.5) * 0.62 + (r.nextBool() ? 0.0 : -0.12),
        big ? 0.030 + r.nextDouble() * 0.018 : 0.012 + r.nextDouble() * 0.014,
        i % 3 == 0 ? -1 : 1,
        2 + r.nextInt(8),
        r.nextDouble() * math.pi * 2,
        big,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = size.width / 2 * 0.80;
    final v = time.value;
    final lv = level.value;
    final p = Paint();
    final halo = Paint();
    for (final d in _dots) {
      final ang = d.angle + v * math.pi * 2 * d.rot; // poora chakkar / loop = seamless (koi jhatka nahi)
      final breath = math.sin(v * math.pi * 2 * d.breathe + d.phase);
      final rr = R * (1 + d.off) + breath * R * (0.022 + 0.05 * lv);
      final o = Offset(c.dx + math.cos(ang) * rr, c.dy + math.sin(ang) * rr);
      final rad = R * d.size * (1 + 0.25 * lv * (0.5 + 0.5 * breath));
      if (d.halo) {
        halo.color = SiyaLight.pink.withOpacity(0.16);
        canvas.drawCircle(o, rad * 2.0, halo);
      }
      p.color = Color.lerp(SiyaLight.pinkDeep, SiyaLight.magenta, d.halo ? 0.0 : 0.25 + 0.2 * (0.5 + 0.5 * breath))!;
      canvas.drawCircle(o, rad, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => false;
}
