import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import 'ai_browser_screen.dart';
import 'call_logs_screen.dart';
import 'kharcha_screen.dart';
import 'location_screen.dart';
import 'smart_contacts_screen.dart';

class _PowerSilkBackground extends StatelessWidget {
  const _PowerSilkBackground({required this.primaryThemeColor});
  final Color primaryThemeColor;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(primaryThemeColor.withOpacity(.09), const Color(0xFFFFF7FB)),
                Colors.white,
                Color.alphaBlend(primaryThemeColor.withOpacity(.07), const Color(0xFFFFEAF4)),
                Color.alphaBlend(primaryThemeColor.withOpacity(.04), const Color(0xFFFFF8FC)),
              ],
              stops: const [0, .40, .78, 1],
            ),
          ),
          child: CustomPaint(
            painter: _PowerSilkPainter(primaryThemeColor),
            size: Size.infinite,
          ),
        ),
      );
}

class _PowerSilkPainter extends CustomPainter {
  const _PowerSilkPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withOpacity(.12),
          accent.withOpacity(.03),
          Colors.transparent,
        ],
        stops: const [0, .55, 1],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .85, size.height * .28),
          radius: size.width * .75,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    final ribbonPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 6; i++) {
      final y = size.height * (.05 + i * .18);
      final ribbon = Path()
        ..moveTo(-size.width * .12, y)
        ..cubicTo(
          size.width * .16, y - size.height * .14,
          size.width * .36, y + size.height * .12,
          size.width * .65, y - size.height * .02,
        )
        ..cubicTo(
          size.width * .86, y - size.height * .09,
          size.width * .97, y + size.height * .09,
          size.width * 1.12, y + size.height * .01,
        )
        ..lineTo(size.width * 1.12, y + size.height * .04)
        ..cubicTo(
          size.width * .86, y + size.height * .16,
          size.width * .66, y + size.height * .05,
          size.width * .40, y + size.height * .11,
        )
        ..cubicTo(
          size.width * .16, y + size.height * .16,
          size.width * .035, y + size.height * .02,
          -size.width * .12, y + size.height * .06,
        )
        ..close();

      ribbonPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(.02),
          accent.withOpacity(i.isEven ? .15 : .08),
          const Color(0xFFFF6EB0).withOpacity(.06),
          Colors.white.withOpacity(.02),
        ],
      ).createShader(
        Rect.fromLTWH(0, y - size.height * .18, size.width, size.height * .36),
      );
      canvas.drawPath(ribbon, ribbonPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PowerSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// PowerScreen: ⚡ Clean Power Tools Dashboard
/// 1. AI Browser -> AiBrowserScreen
/// 2. Smart Location -> LocationScreen
/// 3. Smart Call & Nicknames -> SmartContactsScreen
/// 4. Smart Call Logs -> CallLogsScreen
/// 5. SMS / Kharcha Tracker -> KharchaScreen
class PowerScreen extends StatefulWidget {
  const PowerScreen({
    super.key,
    required this.bridge,
    this.embedded = false,
    this.onBackToHome,
  });

  final SiyaBridge bridge;
  final bool embedded;
  final VoidCallback? onBackToHome;

  @override
  State<PowerScreen> createState() => _PowerScreenState();
}

class _PowerScreenState extends State<PowerScreen> {
  Color get _primaryThemeColor => SiyaTheme.accent.value;

  @override
  void initState() {
    super.initState();
    SiyaTheme.accent.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    SiyaTheme.accent.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Color.alphaBlend(_primaryThemeColor.withOpacity(.045), const Color(0xFFFFF5FA)),
      body: Stack(
        children: [
          Positioned.fill(
            child: _PowerSilkBackground(primaryThemeColor: _primaryThemeColor),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      widget.embedded ? bottomInset + 120 : bottomInset + 32,
                    ),
                    children: [
                      // Hero Info Banner
                      _buildDashboardHeroBanner(),
                      const SizedBox(height: 16),

                      // Card 1: AI Browser
                      _dashboardToolCard(
                        icon: Icons.travel_explore_rounded,
                        badge: 'Web Automation',
                        title: 'AI Browser',
                        subtitle: 'In-app automated web viewer aur live web search',
                        onTap: () {
                          widget.bridge.openBrowser('https://www.google.com');
                        },
                      ),
                      const SizedBox(height: 14),

                      // Card 2: Smart Location
                      _dashboardToolCard(
                        icon: Icons.explore_rounded,
                        badge: 'Live GPS & Map',
                        title: 'Smart Location',
                        subtitle: 'GPS detect, interactive map aur live queries',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LocationScreen(bridge: widget.bridge),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // Card 3: Smart Call & Nicknames
                      _dashboardToolCard(
                        icon: Icons.contact_phone_rounded,
                        badge: 'Voice Call Hub',
                        title: 'Smart Call & Nicknames',
                        subtitle: 'Custom numbers aur multi-nicknames (Papa, Dost) manage karein',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SmartContactsScreen(bridge: widget.bridge),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // Card 4: Smart Call Logs
                      _dashboardToolCard(
                        icon: Icons.phone_in_talk_rounded,
                        badge: 'AI Screener',
                        title: 'Smart Call Logs',
                        subtitle: 'AI-handled calls, caller detection aur history',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CallLogsScreen(bridge: widget.bridge),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // Card 5: SMS / Kharcha Tracker
                      _dashboardToolCard(
                        icon: Icons.account_balance_wallet_rounded,
                        badge: 'Finance & UPI',
                        title: 'SMS / Kharcha Tracker',
                        subtitle: 'Bank & UPI SMS expense sheet aur daily ledger',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => KharchaScreen(bridge: widget.bridge),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _primaryThemeColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: _primaryThemeColor.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryThemeColor.withOpacity(0.22),
                  _primaryThemeColor.withOpacity(0.08),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bolt_rounded, color: _primaryThemeColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Tools Dashboard',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2A1C25),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _primaryThemeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '5 Pro Tools',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _primaryThemeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Har tool ek standalone automated capability hai. Card par tap karke open karein.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B5C67),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardToolCard({
    required IconData icon,
    required String badge,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.78),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(.95), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _primaryThemeColor.withOpacity(.08),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primaryThemeColor.withOpacity(0.22),
                    _primaryThemeColor.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _primaryThemeColor.withOpacity(0.3)),
              ),
              child: Icon(icon, color: _primaryThemeColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF2A1C25),
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primaryThemeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _primaryThemeColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B5C67),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _primaryThemeColor.withOpacity(0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_right_rounded, color: _primaryThemeColor, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            InkWell(
              onTap: () {
                if (widget.onBackToHome != null) {
                  widget.onBackToHome!();
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.9)),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryThemeColor.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: _primaryThemeColor, size: 20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Power Tools ⚡',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2A1C25),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Quick Action & Capability Hub',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primaryThemeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
