import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Hologram mic button.
///  - Band (idle): thanda steel-blue, dheemi saans, halki ghoomti dashed ring.
///  - Click par rang badalta hai aur state ke hisaab se alag effect chalta hai:
///      listening  -> green/cyan, failti hui ripple rings
///      processing -> amber/violet, ghoomte hue orbit arcs + scan line
///      speaking   -> pink/purple, awaaz ke saath radial bars
///  - Tap par ek burst ring bhi niklti hai.
class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.size,
    required this.time,
    required this.level,
    required this.state,
    required this.onTap,
  });

  final double size;
  final Animation<double> time; // 16s repeat controller (home screen ka)
  final ValueListenable<double> level;
  final String state; // idle | waiting | listening | processing | speaking
  final VoidCallback onTap;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _Pal {
  const _Pal(this.a, this.b, this.c, this.energy, this.ripple, this.orbit, this.bars);
  final Color a; // halka (glow / highlight)
  final Color b; // body
  final Color c; // gehra (outer ring)
  final double energy;
  final double ripple;
  final double orbit;
  final double bars;

  static _Pal lerp(_Pal x, _Pal y, double t) => _Pal(
        Color.lerp(x.a, y.a, t)!,
        Color.lerp(x.b, y.b, t)!,
        Color.lerp(x.c, y.c, t)!,
        ui.lerpDouble(x.energy, y.energy, t)!,
        ui.lerpDouble(x.ripple, y.ripple, t)!,
        ui.lerpDouble(x.orbit, y.orbit, t)!,
        ui.lerpDouble(x.bars, y.bars, t)!,
      );

  static const idle = _Pal(Color(0xFF8FB3D9), Color(0xFF3D6A99), Color(0xFF5B5F97), 0.25, 0, 0, 0);
  static const listening = _Pal(Color(0xFF7CFFD8), Color(0xFF00C98D), Color(0xFF22D3EE), 1.0, 1, 0, 0);
  static const processing = _Pal(Color(0xFFFFD27A), Color(0xFFFF9F1C), Color(0xFFB07CFF), 0.85, 0, 1, 0);
  static const speaking = _Pal(Color(0xFFFF9BEA), Color(0xFFD946EF), Color(0xFF8B5CF6), 1.0, 0, 0, 1);

  static _Pal forState(String s) {
    switch (s) {
      case 'listening':
        return listening;
      case 'processing':
      case 'waiting':
        return processing;
      case 'speaking':
        return speaking;
      default:
        return idle;
    }
  }
}

class _MicButtonState extends State<MicButton> with TickerProviderStateMixin {
  late final AnimationController _swap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _burst =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late _Pal _from = _Pal.forState(widget.state);
  late _Pal _to = _Pal.forState(widget.state);
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _swap.value = 1;
  }

  @override
  void didUpdateWidget(covariant MicButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      // abhi ka (beech ka) rang hi naya "from" ban jaata hai -> beech mein bhi smooth badlaav
      _from = _Pal.lerp(_from, _to, Curves.easeInOut.transform(_swap.value));
      _to = _Pal.forState(widget.state);
      _swap.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _swap.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          _burst.forward(from: 0);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _HologramPainter(
                  time: widget.time,
                  level: widget.level,
                  swap: _swap,
                  burst: _burst,
                  from: () => _from,
                  to: () => _to,
                ),
              ),
            ),
          ),
        ),
      );
}

class _HologramPainter extends CustomPainter {
  _HologramPainter({
    required this.time,
    required this.level,
    required this.swap,
    required this.burst,
    required this.from,
    required this.to,
  }) : super(repaint: Listenable.merge([time, level, swap, burst]));

  final Animation<double> time;
  final ValueListenable<double> level;
  final Animation<double> swap;
  final Animation<double> burst;
  final _Pal Function() from;
  final _Pal Function() to;

  @override
  void paint(Canvas canvas, Size size) {
    final pal = _Pal.lerp(from(), to(), Curves.easeInOut.transform(swap.value));
    final t = time.value * 16.0; // seconds
    final c = size.center(Offset.zero);
    final d = size.shortestSide;
    final lv = level.value.clamp(0.0, 1.0);
    final e = pal.energy;
    final breathe = 0.5 + 0.5 * math.sin(t * math.pi * 2 * (0.35 + 0.5 * e));
    final r = d * 0.2 * (1 + 0.035 * breathe + 0.09 * lv * e);

    // 1) bada soft glow
    canvas.drawCircle(
      c,
      r * 3.1,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 3.1, [
          pal.a.withOpacity((0.10 + 0.30 * e + 0.12 * lv).clamp(0.0, 1.0)),
          pal.c.withOpacity((0.05 + 0.16 * e).clamp(0.0, 1.0)),
          Colors.transparent,
        ], const [0.0, 0.55, 1.0]),
    );

    // 2) hologram projector base: neeche ki elliptical plate + halki beam
    final baseY = c.dy + r * 1.78;
    for (int i = 0; i < 3; i++) {
      final w = r * (2.5 - i * 0.55);
      final h = w * 0.26;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.dx, baseY + i * r * 0.05), width: w, height: h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = pal.a.withOpacity(((0.55 - i * 0.14) * (0.45 + 0.55 * e)).clamp(0.0, 1.0)),
      );
    }
    final beam = Path()
      ..moveTo(c.dx - r * 1.05, baseY)
      ..lineTo(c.dx - r * 0.7, c.dy + r * 0.4)
      ..lineTo(c.dx + r * 0.7, c.dy + r * 0.4)
      ..lineTo(c.dx + r * 1.05, baseY)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = ui.Gradient.linear(Offset(c.dx, baseY), Offset(c.dx, c.dy + r * 0.4),
            [pal.a.withOpacity((0.20 * (0.4 + e)).clamp(0.0, 1.0)), Colors.transparent]),
    );

    // 3) ghoomti dashed ring
    final dashRot = t * (0.25 + 0.9 * e);
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = pal.c.withOpacity((0.35 + 0.5 * e).clamp(0.0, 1.0));
    final dashR = r * 2.05;
    for (int i = 0; i < 36; i++) {
      final a0 = dashRot + i * (math.pi * 2 / 36);
      canvas.drawArc(Rect.fromCircle(center: c, radius: dashR), a0, math.pi * 2 / 36 * 0.55, false, dash);
    }

    // 4) ripple rings (listening)
    if (pal.ripple > 0.01) {
      for (int i = 0; i < 3; i++) {
        final ph = (t * 0.8 + i / 3) % 1.0;
        canvas.drawCircle(
          c,
          r * (1.15 + ph * 1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 * (1 - ph) + 0.4
            ..color = pal.a.withOpacity(((1 - ph) * 0.65 * pal.ripple * (0.9 + 0.4 * lv)).clamp(0.0, 1.0)),
        );
      }
    }

    // 5) orbit arcs (processing)
    if (pal.orbit > 0.01) {
      for (int i = 0; i < 3; i++) {
        final rad = r * (1.45 + i * 0.22);
        final dir = i.isEven ? 1.0 : -1.0;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: rad),
          dir * t * (2.2 + i * 1.1) + i * 1.9,
          math.pi * (0.55 + 0.15 * i),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6 - i * 0.5
            ..strokeCap = StrokeCap.round
            ..color = (i == 1 ? pal.c : pal.a).withOpacity((0.9 * pal.orbit).clamp(0.0, 1.0)),
        );
      }
    }

    // 6) radial bars (speaking)
    if (pal.bars > 0.01) {
      const n = 48;
      final bp = Paint()
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = pal.a.withOpacity((0.9 * pal.bars).clamp(0.0, 1.0));
      for (int i = 0; i < n; i++) {
        final ang = i * math.pi * 2 / n;
        final wob = (math.sin(i * 0.9 + t * 9) * 0.5 + 0.5) * (math.sin(i * 0.37 - t * 5).abs());
        final len = r * (0.08 + (0.10 + 0.55 * lv) * wob) * pal.bars;
        final dir = Offset(math.cos(ang), math.sin(ang));
        canvas.drawLine(c + dir * (r * 1.32), c + dir * (r * 1.32 + len), bp);
      }
    }

    // 7) orbit karte chhote sparkle dots
    for (int i = 0; i < 6; i++) {
      final ang = t * (0.4 + 0.6 * e) + i * math.pi / 3;
      final rr = r * (2.35 + 0.08 * math.sin(t * 2 + i));
      final p = c + Offset(math.cos(ang), math.sin(ang)) * rr;
      canvas.drawCircle(p, math.max(1.1, d * 0.012) * (0.6 + 0.8 * e),
          Paint()..color = (i.isEven ? pal.a : pal.c).withOpacity((0.35 + 0.55 * e).clamp(0.0, 1.0)));
    }

    // 8) core orb
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(Offset(c.dx - r * 0.35, c.dy - r * 0.45), r * 1.9,
            [pal.a, pal.b, Color.lerp(pal.c, Colors.black, 0.25)!], const [0.0, 0.52, 1.0]),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withOpacity((0.30 + 0.4 * e).clamp(0.0, 1.0)),
    );

    // hologram scanlines (orb ke andar tak seemit)
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final sl = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity((0.07 + 0.05 * e).clamp(0.0, 1.0));
    for (double y = c.dy - r; y < c.dy + r; y += 4) {
      canvas.drawLine(Offset(c.dx - r, y), Offset(c.dx + r, y), sl);
    }
    final sy = c.dy - r + ((t * (0.35 + 0.5 * e)) % 1.0) * r * 2;
    canvas.drawRect(
      Rect.fromLTWH(c.dx - r, sy - r * 0.12, r * 2, r * 0.24),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, sy - r * 0.12), Offset(0, sy + r * 0.12), [
          Colors.transparent,
          Colors.white.withOpacity((0.28 + 0.2 * e).clamp(0.0, 1.0)),
          Colors.transparent,
        ], const [0.0, 0.5, 1.0]),
    );
    canvas.restore();

    // 9) mic glyph (halka hologram flicker ke saath)
    final flick = 0.9 + 0.1 * math.sin(t * 38);
    final core = Paint()
      ..color = Colors.white.withOpacity(((0.72 + 0.28 * e) * flick).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, r * 0.12)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx, c.dy - r * 0.46), Offset(c.dx, c.dy + r * 0.18), core);
    canvas.drawArc(Rect.fromCenter(center: Offset(c.dx, c.dy - r * 0.03), width: r * 1.18, height: r * 1.45), 0,
        math.pi, false, core);
    canvas.drawLine(Offset(c.dx, c.dy + r * 0.20), Offset(c.dx, c.dy + r * 0.47), core);
    canvas.drawLine(Offset(c.dx - r * 0.28, c.dy + r * 0.47), Offset(c.dx + r * 0.28, c.dy + r * 0.47), core);

    // 10) tap burst
    if (burst.value > 0 && burst.value < 1) {
      final b = burst.value;
      canvas.drawCircle(
        c,
        r * (1.0 + b * 2.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * (1 - b) + 0.5
          ..color = pal.a.withOpacity(((1 - b) * 0.9).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HologramPainter old) => true;
}
