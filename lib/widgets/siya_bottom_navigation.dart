import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Centralized design and labels for Siya AI's bottom navigation.
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
    this.chatActive = false,
    this.toolsActive = false,
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
  final bool chatActive;
  final bool toolsActive;
  final bool settingsActive;

  @override
  Widget build(BuildContext context) {
    final barHeight = (width * .17).clamp(66.0, 80.0);
    final micSize = (width * .21).clamp(80.0, 98.0);
    return SizedBox(
      height: barHeight + micSize * .45,
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
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(primaryColor.withOpacity(0.06), const Color(0xFFFFF9FB)),
                    Color.alphaBlend(primaryColor.withOpacity(0.12), const Color(0xFFFDE8F1)),
                  ],
                ),
                borderRadius: BorderRadius.circular(barHeight * .50),
                border: Border.all(color: const Color(0xCCFFFFFF), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.24),
                    blurRadius: 26,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  const BoxShadow(
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
                    active: chatActive,
                    primaryColor: primaryColor,
                    onTap: onChat,
                  ),

                  // Spacer to accommodate elevated central mic
                  SizedBox(width: micSize * .84),

                  // 4. Tools / Actions Button (to the left of Settings)
                  _SiyaNavItem(
                    icon: Icons.bolt_rounded,
                    tooltip: SiyaNavLabels.tools,
                    active: toolsActive,
                    primaryColor: primaryColor,
                    onTap: onTools,
                  ),

                  // 5. Settings Button
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

          // 3. Central Elevated Glowing Microphone with Light Ripple Animation
          Positioned(
            top: 0,
            child: SizedBox(
              width: micSize * 1.5,
              height: micSize * 1.5,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Expanding radiating neon ripples when mic is active
                  if (active)
                    AnimatedBuilder(
                      animation: time,
                      builder: (context, _) {
                        final t1 = (time.value * 2.2) % 1.0;
                        final t2 = (time.value * 2.2 + 0.5) % 1.0;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: micSize * (1.0 + t1 * 0.44),
                              height: micSize * (1.0 + t1 * 0.44),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: primaryColor.withOpacity((1.0 - t1) * 0.65),
                                  width: 2.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity((1.0 - t1) * 0.35),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: micSize * (1.0 + t2 * 0.44),
                              height: micSize * (1.0 + t2 * 0.44),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: primaryColor.withOpacity((1.0 - t2) * 0.65),
                                  width: 2.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity((1.0 - t2) * 0.35),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                  // Mic Button Main Container
                  AnimatedBuilder(
                    animation: time,
                    builder: (context, child) => Transform.scale(
                      scale: 1 + (active ? .045 : .020) * math.sin(time.value * math.pi * 2),
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
                          onTap: () {
                            Future.microtask(() async {
                              await onMic();
                            });
                          },
                          child: Container(
                            width: micSize,
                            height: micSize,
                            padding: const EdgeInsets.all(4.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.lerp(primaryColor, Colors.white, 0.45)!,
                                  primaryColor,
                                  Color.lerp(primaryColor, const Color(0xFF881254), 0.3)!,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(active ? 0.85 : 0.50),
                                  blurRadius: active ? 32 : 22,
                                  spreadRadius: active ? 4 : 2,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: Color.lerp(primaryColor, Colors.white, 0.55)!.withOpacity(0.6),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  center: const Alignment(-0.25, -0.25),
                                  radius: 0.95,
                                  colors: [
                                    Color.lerp(primaryColor, Colors.white, 0.42)!,
                                    primaryColor.withOpacity(0.95),
                                    Color.lerp(primaryColor, const Color(0xFF650B3E), 0.4)!,
                                  ],
                                ),
                                border: Border.all(
                                  color: Color.lerp(primaryColor, Colors.white, 0.55)!,
                                  width: 2.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(0.55),
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.mic_rounded,
                                  color: Colors.white,
                                  size: micSize * .44,
                                  shadows: [
                                    Shadow(color: primaryColor, blurRadius: active ? 22 : 14),
                                    const Shadow(color: Colors.white, blurRadius: 4),
                                  ],
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Unified navigation item widget.
/// When active: renders the highlighted white squircle card with primary color icon + underline bar.
/// When inactive: renders the circular frosted pink/accent glass button with white icon.
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
                            color: Color.lerp(primaryColor, Colors.white, 0.7)!,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.24),
                              blurRadius: 10,
                              spreadRadius: 1,
                              offset: const Offset(0, 3),
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
                      gradient: RadialGradient(
                        center: const Alignment(-0.2, -0.3),
                        radius: 0.9,
                        colors: [
                          Color.lerp(primaryColor, Colors.white, 0.28)!,
                          primaryColor,
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0x99FFFFFF),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.30),
                          blurRadius: 10,
                          spreadRadius: 1,
                          offset: const Offset(0, 3),
                        ),
                        const BoxShadow(
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
