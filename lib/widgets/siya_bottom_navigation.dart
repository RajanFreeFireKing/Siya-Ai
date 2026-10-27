import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme.dart';

/// Centralized design and labels for Siya AI's bottom navigation.
/// Edit this file to change button names, icons, colors, sizes, or dock styling.
class SiyaNavLabels {
  const SiyaNavLabels._();

  static const String home = 'Home';
  static const String chat = 'Chat';
  static const String tools = 'Tools';
  static const String settings = 'Settings';
  static const String startVoice = 'Start Siya AI voice';
  static const String stopVoice = 'Stop Siya AI voice';
}

class SiyaBottomNavigation extends StatelessWidget {
  const SiyaBottomNavigation({
    super.key,
    required this.width,
    required this.time,
    required this.active,
    required this.onHome,
    required this.onChat,
    required this.onMic,
    required this.onTools,
    required this.onSettings,
    this.primaryColor,
    this.homeActive = true,
    this.settingsActive = false,
  });

  final double width;
  final Animation<double> time;
  final bool active;
  final VoidCallback onHome;
  final VoidCallback onChat;
  final VoidCallback onMic;
  final VoidCallback onTools;
  final VoidCallback onSettings;
  final Color? primaryColor;
  final bool homeActive;
  final bool settingsActive;

  @override
  Widget build(BuildContext context) {
    final accent = primaryColor ?? SiyaTheme.accent.value;
    final barHeight = (width * .185).clamp(74.0, 108.0);
    final micSize = (width * .225).clamp(88.0, 126.0);
    return SizedBox(
      height: barHeight + micSize * .46,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: micSize * .17,
            height: barHeight,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xDDFCE8F2),
                borderRadius: BorderRadius.circular(barHeight * .46),
                border: Border.all(color: const Color(0x99FFFFFF), width: 1.6),
                boxShadow: const [
                  BoxShadow(color: accent.withOpacity(.20), blurRadius: 24, spreadRadius: 1),
                  BoxShadow(color: Color(0xCCFFFFFF), blurRadius: 8, spreadRadius: -2),
                ],
              ),
              child: Row(children: [
                Expanded(child: _SiyaNavItem(icon: Icons.home_rounded, label: SiyaNavLabels.home, active: homeActive, primaryColor: accent, onTap: onHome)),
                Expanded(child: _SiyaNavItem(icon: Icons.chat_bubble_outline_rounded, label: SiyaNavLabels.chat, primaryColor: accent, onTap: onChat)),
                SizedBox(width: micSize * .86),
                Expanded(child: _SiyaNavItem(icon: Icons.bolt_rounded, label: SiyaNavLabels.tools, primaryColor: accent, onTap: onTools)),
                Expanded(child: _SiyaNavItem(icon: Icons.settings_rounded, label: SiyaNavLabels.settings, active: settingsActive, primaryColor: accent, onTap: onSettings)),
              ]),
            ),
          ),
          Positioned(
            top: 0,
            child: AnimatedBuilder(
              animation: time,
              builder: (context, child) => Transform.scale(
                scale: 1 + .018 * math.sin(time.value * math.pi * 2),
                child: child,
              ),
              child: Semantics(
                button: true,
                label: active ? SiyaNavLabels.stopVoice : SiyaNavLabels.startVoice,
                child: Material(
                  color: const Color(0xFFFFF7FB),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onMic,
                    child: Container(
                      width: micSize,
                      height: micSize,
                      padding: EdgeInsets.all(micSize * .07),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: accent.withOpacity(.60), blurRadius: 25, spreadRadius: 3),
                          BoxShadow(color: Color(0x66FF84B4), blurRadius: 12, spreadRadius: 1),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFF020207), Color(0xFF1B0009), Color(0xFFE80046)],
                            stops: [0, .72, 1],
                          ),
                          border: Border.all(color: accent, width: 2.4),
                          boxShadow: const [BoxShadow(color: accent.withOpacity(.48), blurRadius: 18, spreadRadius: 2)],
                        ),
                        child: Icon(
                          active ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: micSize * .37,
                          shadows: const [Shadow(color: Color(0xFFFF1758), blurRadius: 14)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SiyaNavItem extends StatelessWidget {
  const _SiyaNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primaryColor,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color primaryColor;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Colors.white : const Color(0x22FF2B6C),
                    border: Border.all(
                      color: active ? const Color(0xFFFFA5C5) : const Color(0x44FFFFFF),
                      width: active ? 1.4 : 1,
                    ),
                    boxShadow: active
                        ? const [BoxShadow(color: Color(0x33FF205C), blurRadius: 10)]
                        : const [],
                  ),
                  child: Icon(icon, size: 25, color: primaryColor),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.05,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? primaryColor : const Color(0xFF78606D),
                  ),
                ),
                if (active)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 18,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
