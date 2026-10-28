import 'package:flutter/material.dart';

import '../theme.dart';

/// Modern light silk & glassmorphic page container matching HomeScreen & SettingsScreen.
class SiyaPage extends StatelessWidget {
  const SiyaPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SiyaTheme.accent,
      builder: (context, accent, _) {
        return Scaffold(
          backgroundColor: Color.alphaBlend(accent.withOpacity(.045), const Color(0xFFFFF7FB)),
          body: Stack(
            children: [
              // Light silk wave background
              Positioned.fill(
                child: CustomPaint(
                  painter: _SubScreenSilkPainter(accent: accent),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          SiyaIconBtn(
                            icon: Icons.arrow_back_ios_new_rounded,
                            onTap: onBack ?? () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (r) => LinearGradient(
                                colors: [accent, Color.lerp(accent, Colors.black, 0.45)!],
                              ).createShader(r),
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),
                          ...actions,
                        ],
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubScreenSilkPainter extends CustomPainter {
  const _SubScreenSilkPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final ribbonPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (.08 + i * .20);
      final ribbon = Path()
        ..moveTo(-size.width * .12, y)
        ..cubicTo(size.width * .20, y - size.height * .14, size.width * .40, y + size.height * .12, size.width * .68, y - size.height * .03)
        ..cubicTo(size.width * .88, y - size.height * .09, size.width * .98, y + size.height * .08, size.width * 1.12, y)
        ..lineTo(size.width * 1.12, y + size.height * .04)
        ..cubicTo(size.width * .85, y + size.height * .14, size.width * .65, y + size.height * .05, size.width * .38, y + size.height * .10)
        ..cubicTo(size.width * .15, y + size.height * .14, size.width * .02, y + size.height * .02, -size.width * .12, y + size.height * .05)
        ..close();

      ribbonPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(.02),
          accent.withOpacity(i.isEven ? .14 : .07),
          Color.lerp(accent, const Color(0xFFFF6EB0), 0.5)!.withOpacity(.06),
          Colors.white.withOpacity(.02),
        ],
      ).createShader(Rect.fromLTWH(0, y - size.height * .16, size.width, size.height * .32));
      canvas.drawPath(ribbon, ribbonPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SubScreenSilkPainter oldDelegate) => oldDelegate.accent != accent;
}

class SiyaIconBtn extends StatelessWidget {
  const SiyaIconBtn({super.key, required this.icon, required this.onTap, this.danger = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = SiyaTheme.accent.value;
    final color = danger ? const Color(0xFFE50040) : accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Icon(icon, color: danger ? const Color(0xFFE50040) : const Color(0xFF2A1C25), size: 20),
      ),
    );
  }
}

class SiyaCard extends StatelessWidget {
  const SiyaCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final accent = SiyaTheme.accent.value;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}

class SiyaButton extends StatelessWidget {
  const SiyaButton({super.key, required this.label, required this.onTap, this.icon, this.outlined = false});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final accent = SiyaTheme.accent.value;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: outlined
                ? null
                : LinearGradient(colors: [accent, Color.lerp(accent, const Color(0xFFFF0077), 0.5)!]),
            color: outlined ? Colors.white : null,
            border: outlined ? Border.all(color: accent.withOpacity(0.6), width: 1.2) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: outlined ? null : [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 14)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, color: outlined ? accent : Colors.white, size: 20), const SizedBox(width: 8)],
              Text(
                label,
                style: TextStyle(
                  color: outlined ? accent : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration siyaInput(String label, IconData icon) {
  final accent = SiyaTheme.accent.value;
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF756A76)),
    prefixIcon: Icon(icon, color: accent, size: 20),
    filled: true,
    fillColor: const Color(0xFFFFF9FC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: accent.withOpacity(0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: accent.withOpacity(0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: accent, width: 1.4),
    ),
  );
}
