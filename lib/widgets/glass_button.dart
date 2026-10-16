import 'package:flutter/material.dart';

import '../theme.dart';

/// Frosted-glass gol button (settings / mic / X) - design jaisa. BackdropFilter nahi (slow phones par
/// lag karta hai), isliye semi-transparent safed gola + patli border.
class GlassButton extends StatefulWidget {
  const GlassButton({super.key, required this.size, required this.icon, required this.onTap, this.iconColor});

  final double size;
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.55),
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1),
            boxShadow: [BoxShadow(color: SiyaLight.pink.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: Icon(widget.icon, color: widget.iconColor ?? SiyaLight.pink, size: widget.size * 0.44),
        ),
      ),
    );
  }
}
