import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/wallpaper_layer.dart';
import '../widgets/wave_painter.dart';
import '../widgets/siya_bottom_navigation.dart';
import 'features_screen.dart';
import 'settings_screen.dart';

/// Siya AI persistent root shell with home screen and integrated tab navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.bridge});
  final SiyaBridge bridge;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctrl;
  late final AnimationController _intro;
  final ValueNotifier<double> _level = ValueNotifier<double>(0.0);
  final TextEditingController _message = TextEditingController();
  final FocusNode _messageFocus = FocusNode();

  int _activeTab = 0; // 0: Home, 1: Chat, 2: Tools (Features), 3: Settings

  String _wpType = 'none';
  String _wpPath = '';
  bool _wpSound = false;
  double _wpDim = 0.08;

  Future<void> _loadWallpaper() async {
    try {
      final s = await widget.bridge.getSettings();
      if (!mounted) return;
      setState(() {
        _wpType = (s['wallpaper_type'] as String?) ?? 'none';
        _wpPath = (s['wallpaper_path'] as String?) ?? '';
        _wpSound = (s['wallpaper_sound'] as bool?) ?? false;
        _wpDim = ((s['wallpaper_dim'] as num?) ?? 0.08).toDouble();
      });
    } catch (_) {}
  }

  Animation<double> _iv(double a, double b, Curve c) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
    _ctrl.addListener(_tick);
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..forward();
    widget.bridge.listen();
    widget.bridge.addListener(_onBridgeChanged);
    widget.bridge.error.addListener(_onError);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.bridge.init();
      _loadWallpaper();
      try {
        if (await widget.bridge.consumeFirstRun()) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          if (mounted) await widget.bridge.requestPermissions();
        }
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _ctrl.stop();
    }
  }

  void _onBridgeChanged() {
    if (mounted) setState(() {});
  }

  void _onError() {
    final code = widget.bridge.error.value;
    if (code == null || !mounted) return;
    widget.bridge.error.value = null;
    final msg = switch (code) {
      'no_key' => 'Settings mein Gemini API Key daalo',
      'no_mic' => 'Mic permission chahiye',
      'connection' => 'Connection nahi ho paya. Internet / API key check karo',
      _ => 'Kuch gadbad hui, dobara try karo',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF7D174F),
        action: code == 'no_key'
            ? SnackBarAction(label: 'Settings', textColor: Colors.white, onPressed: () => setState(() => _activeTab = 3))
            : null,
      ));
  }

  void _tick() {
    final b = widget.bridge;
    double target;
    if (!b.isActive) {
      target = 0.0;
    } else {
      switch (b.state) {
        case 'listening':
          target = 0.20 + 0.80 * b.amp.value;
          break;
        case 'speaking':
          target = 0.50 + 0.50 * math.sin(_ctrl.value * math.pi * 2 * 36).abs();
          break;
        case 'processing':
        case 'waiting':
          target = 0.25;
          break;
        default:
          target = 0.0;
      }
    }
    _level.value += (target - _level.value) * 0.16;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.bridge.removeListener(_onBridgeChanged);
    widget.bridge.error.removeListener(_onError);
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
    _intro.dispose();
    _level.dispose();
    _message.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_message.text.trim().isEmpty) return;
    _message.clear();
    _messageFocus.unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Voice interaction ke liye center mic button tap karein.'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SiyaTheme.accent,
      builder: (context, accent, _) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: Color.alphaBlend(accent.withOpacity(.045), const Color(0xFFFFF7FB)),
            resizeToAvoidBottomInset: false,
            body: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final safeBottom = MediaQuery.of(context).viewInsets.bottom > 0
                  ? 10.0
                  : MediaQuery.of(context).padding.bottom;
              final compact = h < 730;
              final ring = math.min(w * 0.55, h * (compact ? 0.245 : 0.275));

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Persistent body depending on active tab
                  IndexedStack(
                    index: _activeTab,
                    children: [
                      // Tab 0: Home view
                      _buildHomeView(w, h, compact, ring, safeBottom, accent),

                      // Tab 1: Chat view
                      _buildChatView(w, h, compact, safeBottom, accent),

                      // Tab 2: Tools (Features) view (embedded with persistent dock)
                      FeaturesScreen(
                        bridge: widget.bridge,
                        embedded: true,
                        onBackToHome: () => setState(() => _activeTab = 0),
                      ),

                      // Tab 3: Settings view (embedded with persistent dock)
                      SettingsScreen(
                        bridge: widget.bridge,
                        embedded: true,
                        onBackToHome: () => setState(() => _activeTab = 0),
                      ),
                    ],
                  ),

                  // Single Persistent Floating Bottom Navigation Dock
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: math.max(12.0, safeBottom + 6.0),
                    child: FadeTransition(
                      opacity: _iv(.25, 1, Curves.easeOut),
                      child: SiyaBottomNavigation(
                        width: w * .93,
                        primaryColor: accent,
                        time: _ctrl,
                        active: widget.bridge.isActive,
                        homeActive: _activeTab == 0,
                        chatActive: _activeTab == 1,
                        toolsActive: _activeTab == 2,
                        settingsActive: _activeTab == 3,
                        onHome: () => setState(() => _activeTab = 0),
                        onChat: () => setState(() => _activeTab = 1),
                        onMic: widget.bridge.toggleMic,
                        onTools: () => setState(() => _activeTab = 2),
                        onSettings: () => setState(() => _activeTab = 3),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  // ── Tab 0: Home View ──────────────────────────────────────────
  Widget _buildHomeView(double w, double h, bool compact, double ring, double safeBottom, Color accent) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _ReferenceBackground(accent: accent),
        Positioned.fill(
          child: IgnorePointer(
            child: WallpaperLayer(type: _wpType, path: _wpPath, sound: _wpSound, dim: _wpDim),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top header: Brand logo + circular notification button
              Padding(
                padding: EdgeInsets.fromLTRB(w * 0.055, 8, w * 0.055, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _BrandTitle(width: w, accent: accent),
                    _NotificationButton(
                      accent: accent,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Abhi koi nayi notification nahi hai.'),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: h * (compact ? 0.026 : 0.040)),

              // Center Glowing Orb with Animated Soundwaves radiating from sides
              FadeTransition(
                opacity: _iv(0.05, 0.72, Curves.easeOut),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.88, end: 1).animate(_iv(0.02, 0.8, Curves.easeOutBack)),
                  child: SizedBox(
                    width: ring * 1.35,
                    height: ring * 1.35,
                    child: AnimatedBuilder(
                      animation: widget.bridge,
                      builder: (_, __) => _CoreLogo(
                        size: ring,
                        time: _ctrl,
                        level: _level,
                        active: widget.bridge.isActive,
                        accent: accent,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: h * (compact ? 0.012 : 0.020)),

              // Heading "Hello!" / "Here for you"
              Text(
                _greeting,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF0C0D15),
                  fontSize: (w * 0.088).clamp(30.0, 38.0),
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),

              // Subtitle "How can I help you today?"
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF4E5565),
                    fontSize: (w * 0.046).clamp(16.0, 19.5),
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              SizedBox(height: h * (compact ? 0.022 : 0.034)),

              // Audio Waveform Visualizer - lifted up to balanced position
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * .055),
                child: Container(
                  height: compact ? 64 : 76,
                  decoration: BoxDecoration(
                    color: const Color(0x35FFFFFF),
                    borderRadius: BorderRadius.circular(38),
                    border: Border.all(color: const Color(0x88FFFFFF), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.18),
                        blurRadius: 20,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                      const BoxShadow(
                        color: Color(0x88FFFFFF),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, __) => CustomPaint(
                      painter: SiyaWavePainter(
                        time: _ctrl,
                        level: _level,
                        active: widget.bridge.isActive,
                        primaryColor: accent,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

              // Flexible space below waveform for breathing room above the dock
              const Spacer(),
              const SizedBox(height: 86),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 1: Chat View ──────────────────────────────────────────
  Widget _buildChatView(double w, double h, bool compact, double safeBottom, Color accent) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _ReferenceBackground(accent: accent),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Chat Header
              Padding(
                padding: EdgeInsets.fromLTRB(w * 0.055, 8, w * 0.055, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _BrandTitle(width: w, accent: accent),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mic_none_rounded, color: accent, size: 16),
                          const SizedBox(width: 4),
                          Text('Voice Active', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Chat content / dialogue history
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.82),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white, width: 1.4),
                          boxShadow: [
                            BoxShadow(color: accent.withOpacity(0.10), blurRadius: 24, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [accent, Color.lerp(accent, Colors.white, 0.4)!]),
                                boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 16)],
                              ),
                              child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Siya AI Conversation',
                              style: TextStyle(color: Color(0xFF151019), fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            ValueListenableBuilder<String>(
                              valueListenable: widget.bridge.transcript,
                              builder: (context, transcript, _) {
                                final text = transcript.isNotEmpty
                                    ? transcript
                                    : (widget.bridge.status.isNotEmpty
                                        ? widget.bridge.status
                                        : 'Aap bol kar ya neeche mic tap karke sawaal poochh sakte hain.');
                                return Text(
                                  text,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: transcript.isNotEmpty ? const Color(0xFF151019) : const Color(0xFF6F6470),
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Input text box
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, safeBottom + 94),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: accent.withOpacity(0.3), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: accent.withOpacity(0.12), blurRadius: 18, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _message,
                          focusNode: _messageFocus,
                          onSubmitted: (_) => _sendMessage(),
                          style: const TextStyle(color: Color(0xFF1E232F)),
                          decoration: const InputDecoration(
                            hintText: 'Type a message to Siya...',
                            hintStyle: TextStyle(color: Color(0xFF8B8A95), fontSize: 14),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send_rounded, color: accent),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _greeting {
    switch (widget.bridge.state) {
      case 'listening':
        return 'I’m listening';
      case 'processing':
      case 'waiting':
        return 'One moment…';
      case 'speaking':
        return 'Here for you';
      default:
        return 'Hello!';
    }
  }

  String get _subtitle {
    switch (widget.bridge.state) {
      case 'listening':
        return 'Go ahead, I’m listening';
      case 'processing':
      case 'waiting':
        return 'Preparing your response…';
      case 'speaking':
        return 'Siya AI is speaking';
      default:
        return 'How can I help you today?';
    }
  }
}

// ── Silk Background & Wave Ribbon Rendering ───────────────────────
class _ReferenceBackground extends StatelessWidget {
  const _ReferenceBackground({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(accent.withOpacity(.04), const Color(0xFFFFF8FC)),
              Colors.white,
              Color.alphaBlend(accent.withOpacity(.06), const Color(0xFFFFF2F9)),
              Color.alphaBlend(accent.withOpacity(.03), const Color(0xFFFFF9FC)),
            ],
            stops: const [0, .38, .76, 1],
          ),
        ),
        child: CustomPaint(painter: _SilkWavePainter(accent), size: Size.infinite),
      );
}

class _SilkWavePainter extends CustomPainter {
  const _SilkWavePainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    for (int i = 0; i < 6; i++) {
      final y = size.height * (.10 + i * .16);
      final path = Path()
        ..moveTo(-size.width * .15, y - size.height * .08)
        ..cubicTo(size.width * .20, y - size.height * .20, size.width * .40, y + size.height * .14, size.width * .68, y - size.height * .02)
        ..cubicTo(size.width * .88, y - size.height * .12, size.width * .98, y + size.height * .10, size.width * 1.15, y - size.height * .02)
        ..lineTo(size.width * 1.15, y + size.height * .045)
        ..cubicTo(size.width * .86, y + size.height * .18, size.width * .68, y + size.height * .06, size.width * .40, y + size.height * .12)
        ..cubicTo(size.width * .18, y + size.height * .16, size.width * .04, y - size.height * .03, -size.width * .15, y + size.height * .05)
        ..close();

      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.01),
          accent.withOpacity(i.isEven ? .28 : .16),
          Color.lerp(accent, const Color(0xFFFF4893), 0.5)!.withOpacity(.14),
          Colors.white.withOpacity(0.01),
        ],
      ).createShader(Rect.fromLTWH(0, y - size.height * .18, size.width, size.height * .36));
      canvas.drawPath(path, paint);

      highlightPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          accent.withOpacity(0.35),
          Colors.white.withOpacity(0.55),
          accent.withOpacity(0.30),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(-size.width * .15, y - size.height * .15, size.width * 1.3, size.height * .3));

      final crestPath = Path()
        ..moveTo(-size.width * .15, y - size.height * .08)
        ..cubicTo(size.width * .20, y - size.height * .20, size.width * .40, y + size.height * .14, size.width * .68, y - size.height * .02)
        ..cubicTo(size.width * .88, y - size.height * .12, size.width * .98, y + size.height * .10, size.width * 1.15, y - size.height * .02);
      canvas.drawPath(crestPath, highlightPaint);
    }

    const normalizedDots = <Offset>[
      Offset(.08, .12), Offset(.18, .20), Offset(.24, .27), Offset(.66, .16),
      Offset(.84, .14), Offset(.90, .24), Offset(.12, .44), Offset(.83, .40),
      Offset(.77, .58), Offset(.28, .70), Offset(.52, .32), Offset(.44, .78),
    ];
    for (int i = 0; i < normalizedDots.length; i++) {
      final dot = Offset(size.width * normalizedDots[i].dx, size.height * normalizedDots[i].dy);
      final r = size.width * (i % 3 == 0 ? .012 : .008);
      canvas.drawCircle(dot, r * 2.5, Paint()..color = accent.withOpacity(0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(dot, r, Paint()..shader = RadialGradient(
        colors: [Color.lerp(accent, Colors.white, 0.45)!, accent],
      ).createShader(Rect.fromCircle(center: dot, radius: r)));
    }
  }

  @override
  bool shouldRepaint(covariant _SilkWavePainter oldDelegate) => oldDelegate.accent != accent;
}

// ── Radiating Side Sound Waves around Hologram ─────────────────────
class _OrbSideWavesPainter extends CustomPainter {
  _OrbSideWavesPainter({required this.time, required this.active, required this.accent})
      : super(repaint: time);

  final Animation<double> time;
  final bool active;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.36;

    for (int i = 0; i < 3; i++) {
      final wavePhase = (time.value * 1.6 + i * 0.33) % 1.0;
      final r = baseR + wavePhase * (size.width * 0.16);
      final alpha = (1.0 - wavePhase) * (active ? 0.75 : 0.35);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 - wavePhase * 1.0
        ..color = accent.withOpacity(alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 + wavePhase * 3.0);

      // Left sound wave arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        math.pi * 0.72,
        math.pi * 0.56,
        false,
        paint,
      );

      // Right sound wave arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi * 0.28,
        math.pi * 0.56,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbSideWavesPainter oldDelegate) => true;
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.width, required this.accent});
  final double width;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _VectorBrandTitle(width: width, accent: accent);
  }
}

class _VectorBrandTitle extends StatelessWidget {
  const _VectorBrandTitle({required this.width, required this.accent});
  final double width;
  final Color accent;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SIYA',
              style: TextStyle(
                fontSize: (width * .083).clamp(36.0, 52.0),
                height: .96,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: -2,
                color: const Color(0xFF08070D),
                shadows: [
                  Shadow(color: accent.withOpacity(0.30), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(width: 7),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                colors: [accent, Color.lerp(accent, Colors.white, 0.45)!],
              ).createShader(r),
              child: Text(
                'AI',
                style: TextStyle(
                  fontSize: (width * .083).clamp(36.0, 52.0),
                  height: .96,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ],
        ),
      );
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap, required this.accent});
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: accent.withOpacity(0.25),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFF2E2EC), width: 1.2),
              boxShadow: [
                BoxShadow(color: accent.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 3)),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none_rounded, color: Color(0xFF16161D), size: 26),
                Positioned(
                  right: 11,
                  top: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: accent.withOpacity(0.6), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _CoreLogo extends StatelessWidget {
  const _CoreLogo({
    required this.size,
    required this.time,
    required this.level,
    required this.active,
    required this.accent,
  });

  final double size;
  final Animation<double> time;
  final ValueListenable<double> level;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (context, lvl, _) {
        return AnimatedBuilder(
          animation: time,
          builder: (context, child) {
            final pulse = (active ? 0.040 : 0.015) * math.sin(time.value * math.pi * 2) + lvl * 0.05;
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Radiating colorful side sound wave arcs (from image 2)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OrbSideWavesPainter(
                      time: time,
                      active: active,
                      accent: accent,
                    ),
                  ),
                ),

                // Center Hologram Orb (100% Vector Code - Dynamic Theme Color)
                Transform.scale(
                  scale: 1.0 + pulse,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: _VectorCoreLogo(
                      size: size,
                      time: time,
                      level: level,
                      active: active,
                      accent: accent,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

void _drawSparkle(Canvas canvas, Offset center, double radius, Color color) {
  final path = Path()
    ..moveTo(center.dx, center.dy - radius)
    ..cubicTo(center.dx, center.dy - radius * 0.2, center.dx + radius * 0.2, center.dy, center.dx + radius, center.dy)
    ..cubicTo(center.dx + radius * 0.2, center.dy, center.dx, center.dy + radius * 0.2, center.dx, center.dy + radius)
    ..cubicTo(center.dx, center.dy + radius * 0.2, center.dx - radius * 0.2, center.dy, center.dx - radius, center.dy)
    ..cubicTo(center.dx - radius * 0.2, center.dy, center.dx, center.dy - radius * 0.2, center.dx, center.dy - radius)
    ..close();

  canvas.drawPath(
    path,
    Paint()
      ..color = color.withOpacity(0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.drawPath(path, Paint()..color = Colors.white);
}

class _VectorCoreLogo extends StatelessWidget {
  const _VectorCoreLogo({
    required this.size,
    required this.time,
    required this.level,
    required this.active,
    required this.accent,
  });

  final double size;
  final Animation<double> time;
  final ValueListenable<double> level;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final deepAccentShade = Color.lerp(accent, const Color(0xFF0C0612), 0.88)!;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Deep Glossy Hologram Sphere with dynamic glow
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.85,
              colors: [
                deepAccentShade,
                const Color(0xFF060308),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(active ? 0.75 : 0.45),
                blurRadius: active ? 36 : 24,
                spreadRadius: active ? 4 : 2,
              ),
              BoxShadow(
                color: Color.lerp(accent, Colors.white, 0.45)!.withOpacity(0.30),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
        ),

        // Floating dynamic sparks & twinkling stars
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _OrbSparksPainter(time: time, level: level, accent: accent),
            ),
          ),
        ),

        // Dynamic S-Flame Vector Logo with glowing halo & 4-point star sparkle
        Positioned(
          top: size * .18,
          left: size * .16,
          right: size * .16,
          bottom: size * .22,
          child: CustomPaint(
            painter: _SiyaGlyphPainter(time: time, active: active, accent: accent),
          ),
        ),

        // "SIYA AI" Futuristic Brand Text
        Positioned(
          bottom: size * .185,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SIYA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * .095,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    fontStyle: FontStyle.italic,
                    shadows: [
                      Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.auto_awesome, color: accent, size: size * .055),
                const SizedBox(width: 4),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.white, 0.65)!],
                  ).createShader(r),
                  child: Text(
                    'AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * .095,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Glowing horizontal beam underline below SIYA AI
        Positioned(
          bottom: size * .135,
          child: Container(
            width: size * .34,
            height: 1.8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  accent.withOpacity(0.85),
                  Color.lerp(accent, Colors.white, 0.7)!,
                  accent.withOpacity(0.85),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
              boxShadow: [
                BoxShadow(color: accent.withOpacity(0.6), blurRadius: 6),
              ],
            ),
          ),
        ),

        // Outer Neon Ring with Rotating SweepGradient & Multiple Bloom Glows
        Positioned.fill(
          child: CustomPaint(
            painter: _OrbRingPainter(time: time, level: level, accent: accent),
          ),
        ),
      ],
    );
  }
}

class _SiyaGlyphPainter extends CustomPainter {
  const _SiyaGlyphPainter({required this.time, required this.active, required this.accent});
  final Animation<double> time;
  final bool active;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p = Path()
      ..moveTo(w * .72, h * .04)
      ..cubicTo(w * .42, h * .02, w * .14, h * .22, w * .28, h * .46)
      ..cubicTo(w * .38, h * .62, w * .68, h * .60, w * .76, h * .74)
      ..cubicTo(w * .84, h * .88, w * .66, h * .98, w * .48, h * .98)
      ..cubicTo(w * .26, h * .98, w * .14, h * .85, w * .14, h * .74)
      ..lineTo(w * .04, h * .76)
      ..cubicTo(w * .06, h * .95, w * .24, 1.05 * h, w * .48, 1.05 * h)
      ..cubicTo(w * .80, 1.05 * h, 1.02 * w, h * .86, w * .88, h * .64)
      ..cubicTo(w * .78, h * .48, w * .46, h * .50, w * .38, h * .36)
      ..cubicTo(w * .30, h * .22, w * .48, h * .12, w * .68, h * .12)
      ..close();

    // Outer glow under flame
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = accent.withOpacity(active ? 0.65 : 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(p, glowPaint);

    // Dynamic gradient flame matching accent
    final flamePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color.lerp(accent, Colors.white, 0.65)!,
          accent,
          Color.lerp(accent, Colors.black, 0.35)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawPath(p, flamePaint);

    // Inner highlight rim along top edge
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Color.lerp(accent, Colors.white, 0.85)!;
    final rimPath = Path()
      ..moveTo(w * .68, h * .12)
      ..cubicTo(w * .48, h * .12, w * .30, h * .22, w * .38, h * .36)
      ..cubicTo(w * .46, h * .50, w * .78, h * .48, w * .88, h * .64);
    canvas.drawPath(rimPath, rimPaint);

    // 4-point sparkle star on upper right curve of S
    final sparkleCenter = Offset(w * 0.78, h * 0.32);
    _drawSparkle(canvas, sparkleCenter, 5.5, accent);
  }

  @override
  bool shouldRepaint(covariant _SiyaGlyphPainter oldDelegate) =>
      oldDelegate.active != active || oldDelegate.accent != accent;
}

class _OrbRingPainter extends CustomPainter {
  const _OrbRingPainter({required this.time, required this.level, required this.accent});
  final Animation<double> time;
  final ValueListenable<double> level;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * .485;

    // Deep neon glow halo
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..color = accent.withOpacity(0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(c, r, glow);

    // Inner bright bloom
    final innerBloom = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Color.lerp(accent, Colors.white, 0.5)!.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(c, r, innerBloom);

    // Rotating SweepGradient ring line
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..shader = SweepGradient(
        colors: [
          Color.lerp(accent, Colors.white, 0.7)!,
          accent,
          Color.lerp(accent, Colors.white, 0.2)!,
          Color.lerp(accent, Colors.black, 0.3)!,
          Color.lerp(accent, Colors.white, 0.7)!,
        ],
        stops: const [0.0, 0.3, 0.6, 0.85, 1.0],
        transform: GradientRotation(time.value * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, line);
  }

  @override
  bool shouldRepaint(covariant _OrbRingPainter oldDelegate) => true;
}

class _OrbSparksPainter extends CustomPainter {
  const _OrbSparksPainter({required this.time, required this.level, required this.accent});
  final Animation<double> time;
  final ValueListenable<double> level;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * .38;
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 20; i++) {
      final speed = i.isEven ? 1.0 : -0.7;
      final angle = (i / 20) * math.pi * 2 + time.value * math.pi * 2 * speed * 0.15;
      final distFrac = 0.35 + 0.55 * ((i * 47) % 100 / 100.0);
      final dist = baseR * distFrac;
      final pos = Offset(c.dx + math.cos(angle) * dist, c.dy + math.sin(angle) * dist);

      final pulse = math.sin(time.value * math.pi * 3 + i * 1.5).abs();
      final alpha = (0.35 + 0.65 * pulse).clamp(0.0, 1.0);

      if (i % 5 == 0) {
        _drawSparkle(canvas, pos, 2.5 + pulse * 2.0, accent);
      } else {
        final r = 1.0 + 1.8 * pulse;
        dotPaint.color = Color.lerp(accent, Colors.white, i % 3 == 0 ? 0.7 : 0.2)!.withOpacity(alpha);
        canvas.drawCircle(pos, r, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbSparksPainter oldDelegate) => true;
}
