import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    this.primaryColor = const Color(0xFFE6004C),
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
  final Color primaryColor;
  final bool homeActive;
  final bool settingsActive;

  @override
  Widget build(BuildContext context) {
    final barHeight = (width * .17).clamp(66.0, 80.0);
    final micSize = (width * .21).clamp(80.0, 98.0);
    return SizedBox(
      height: barHeight + micSize * .42,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Glassmorphic navigation dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            height: barHeight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xF0FFF1F7),
                    Color(0xE6FEE4EE),
                  ],
                ),
                borderRadius: BorderRadius.circular(barHeight * .50),
                border: Border.all(color: const Color(0xCCFFFFFF), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x35FF2A75),
                    blurRadius: 26,
                    spreadRadius: 2,
                    offset: Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Color(0x99FFFFFF),
                    blurRadius: 10,
                    spreadRadius: -2,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. Home Button
                  _SiyaNavItem(
                    icon: Icons.home_rounded,
                    tooltip: SiyaNavLabels.home,
                    active: homeActive,
                    primaryColor: primaryColor,
                    onTap: onHome,
                  ),

                  // 2. Chat Button
                  _SiyaNavItem(
                    icon: Icons.chat_bubble_rounded,
                    tooltip: SiyaNavLabels.chat,
                    primaryColor: primaryColor,
                    onTap: onChat,
                  ),

                  // Spacer to accommodate elevated central mic
                  SizedBox(width: micSize * .84),

                  // 4. Tools / Actions Button
                  _SiyaNavItem(
                    icon: Icons.bolt_rounded,
                    tooltip: SiyaNavLabels.tools,
                    primaryColor: primaryColor,
                    onTap: onTools,
                  ),

                  // 5. Settings Button (Properly highlights active card when on Settings screen)
                  _SiyaNavItem(
                    icon: Icons.settings_rounded,
                    tooltip: SiyaNavLabels.settings,
                    active: settingsActive,
                    primaryColor: primaryColor,
                    onTap: onSettings,
                  ),
                ],
              ),
            ),
          ),

          // 3. Central Elevated Glowing Microphone
          Positioned(
            top: 0,
            child: AnimatedBuilder(
              animation: time,
              builder: (context, child) => Transform.scale(
                scale: 1 + (active ? .035 : .018) * math.sin(time.value * math.pi * 2),
                child: child,
              ),
              child: Semantics(
                button: true,
                label: active ? SiyaNavLabels.stopVoice : SiyaNavLabels.startVoice,
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onMic,
                    child: Container(
                      width: micSize,
                      height: micSize,
                      padding: const EdgeInsets.all(4.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFF528E),
                            Color(0xFFFF1B67),
                            Color(0xFFE50040),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(active ? 0xCCFF003C : 0x88FF1B67),
                            blurRadius: active ? 28 : 22,
                            spreadRadius: active ? 4 : 2,
                            offset: const Offset(0, 4),
                          ),
                          const BoxShadow(
                            color: Color(0x66FFA0C8),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0D0208),
                          border: Border.all(
                            color: const Color(0xFFFF4884),
                            width: 2.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66FF003C),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            active ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: micSize * .42,
                            shadows: const [
                              Shadow(color: Color(0xFFFF1758), blurRadius: 14),
                              Shadow(color: Colors.white, blurRadius: 4),
                            ],
                          ),
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

/// Unified navigation item widget.
/// When active: renders the highlighted white squircle card with primary color icon + underline bar.
/// When inactive: renders the circular frosted pink glass button with white icon.
class _SiyaNavItem extends StatelessWidget {
  const _SiyaNavItem({
    required this.icon,
    required this.tooltip,
    required this.primaryColor,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final Color primaryColor;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: active
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 46,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFFC2D8),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x28FF1F68),
                              blurRadius: 10,
                              spreadRadius: 1,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            icon,
                            size: 26,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 20,
                        height: 3,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.6),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.2, -0.3),
                        radius: 0.9,
                        colors: [
                          Color(0xFFFE3D82),
                          Color(0xFFE60048),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0x99FFFFFF),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x30FF1E64),
                          blurRadius: 10,
                          spreadRadius: 1,
                          offset: Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Color(0x44FFFFFF),
                          blurRadius: 4,
                          spreadRadius: -1,
                          offset: Offset(0, -1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 22,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}


