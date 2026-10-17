import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Compact floating Aurora activator with two animated satellite actions.
class SiyaOrbButton extends StatefulWidget {
  const SiyaOrbButton({super.key, required this.time, required this.isActive, required this.micMuted, required this.onMicTap, required this.onMinimize});

  final Animation<double> time;
  final bool isActive;
  final bool micMuted;
  final VoidCallback onMicTap;
  final VoidCallback onMinimize;

  @override
  State<SiyaOrbButton> createState() => _SiyaOrbButtonState();
}

class _SiyaOrbButtonState extends State<SiyaOrbButton> with SingleTickerProviderStateMixin {
  late final AnimationController _expand = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  bool _expanded = false;

  @override
  void dispose() { _expand.dispose(); super.dispose(); }

  void _toggleExpanded() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) { _expand.forward(); } else { _expand.reverse(); }
  }

  Widget _satellite({required IconData icon, required String tooltip, required VoidCallback onTap, required double dx, required Color glow}) {
    return AnimatedBuilder(
      animation: _expand,
      builder: (context, child) => Transform.translate(
        offset: Offset(dx * Curves.easeOutBack.transform(_expand.value), 0),
        child: Transform.scale(scale: 0.72 + 0.28 * _expand.value, child: Opacity(opacity: _expand.value, child: child)),
      ),
      child: IgnorePointer(
        ignoring: !_expanded,
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: const Color(0xF21B1032),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () { HapticFeedback.lightImpact(); onTap(); },
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: glow.withOpacity(0.78)),
                  boxShadow: [BoxShadow(color: glow.withOpacity(0.22), blurRadius: 18, spreadRadius: 1)]),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      width: 214,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 6, child: _satellite(icon: widget.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            tooltip: widget.micMuted ? 'Unmute microphone' : 'Mute microphone', onTap: widget.onMicTap, dx: 48, glow: widget.micMuted ? const Color(0xFFFF718B) : const Color(0xFFB58CFF))),
          Positioned(right: 6, child: _satellite(icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Minimize to floating overlay', onTap: widget.onMinimize, dx: -48, glow: const Color(0xFF8C6BFF))),
          AnimatedBuilder(
            animation: widget.time,
            builder: (context, child) => Transform.scale(
              scale: 1 + 0.035 * math.sin(widget.time.value * math.pi * 2),
              child: child,
            ),
            child: Material(
              color: const Color(0xFF180D32),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggleExpanded,
                child: Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFFB995FF), Color(0xFF7C4DDB), Color(0xFF47218B)]),
                    border: Border.all(color: const Color(0xFFE6D7FF).withOpacity(0.88), width: 1.2),
                    boxShadow: [BoxShadow(color: SiyaColors.purple.withOpacity(0.52), blurRadius: 24, spreadRadius: 2),
                      BoxShadow(color: const Color(0xFF9C6AFF).withOpacity(0.18), blurRadius: 4, spreadRadius: 1)]),
                  child: Icon(_expanded ? Icons.close_rounded : (widget.isActive ? Icons.graphic_eq_rounded : Icons.auto_awesome_rounded),
                    color: Colors.white, size: 25),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
