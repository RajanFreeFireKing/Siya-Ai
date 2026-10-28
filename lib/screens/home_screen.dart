import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/wallpaper_layer.dart';
import '../widgets/wave_painter.dart';
import '../widgets/siya_bottom_navigation.dart';
import '../widgets/permission_explanation_sheet.dart';
import 'power_screen.dart';
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
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
          if (mounted) await showThemedPermissionSheet(context, widget.bridge);
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
          target = 0.50 + 0.50 * math.sin(_ctrl.value * math.pi * 2 * 10).abs();
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

                      // Tab 2: Tools (Power Tools) view (embedded with persistent dock)
                      PowerScreen(
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
        _ReferenceBackground(accent: accent, time: _ctrl),
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
        _ReferenceBackground(accent: accent, time: _ctrl),
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
class _DropletData {
  const _DropletData({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.phase,
    this.speed = 1.0,
  });
  final double dx;
  final double dy;
  final double radius;
  final double phase;
  final double speed;
}

const _kDroplets = <_DropletData>[
  _DropletData(dx: 0.055, dy: 0.118, radius: 4.8, phase: 0.0),
  _DropletData(dx: 0.158, dy: 0.162, radius: 3.6, phase: 1.2),
  _DropletData(dx: 0.220, dy: 0.180, radius: 3.0, phase: 2.1),
  _DropletData(dx: 0.645, dy: 0.145, radius: 3.8, phase: 0.8),
  _DropletData(dx: 0.820, dy: 0.125, radius: 3.2, phase: 2.8),
  _DropletData(dx: 0.880, dy: 0.185, radius: 4.4, phase: 1.9),
  _DropletData(dx: 0.030, dy: 0.255, radius: 5.2, phase: 3.4),
  _DropletData(dx: 0.118, dy: 0.375, radius: 5.6, phase: 0.4),
  _DropletData(dx: 0.290, dy: 0.410, radius: 3.8, phase: 2.5),
  _DropletData(dx: 0.805, dy: 0.355, radius: 4.6, phase: 1.5),
  _DropletData(dx: 0.748, dy: 0.448, radius: 4.0, phase: 3.1),
  _DropletData(dx: 0.086, dy: 0.585, radius: 3.4, phase: 0.9),
  _DropletData(dx: 0.910, dy: 0.585, radius: 3.4, phase: 2.3),
];

void _draw3DDroplet(Canvas canvas, Offset center, double r, Color accent) {
  // 1. Soft colored drop shadow on surface underneath
  final shadowOffset = Offset(center.dx + r * 0.28, center.dy + r * 0.42);
  canvas.drawCircle(
    shadowOffset,
    r * 1.18,
    Paint()
      ..color = Color.lerp(accent, Colors.black, 0.45)!.withOpacity(0.36)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.75),
  );

  // 2. 3D Sphere Body with Radial Gradient (focal point shifted top-left)
  final sphereRect = Rect.fromCircle(center: center, radius: r);
  final spherePaint = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.38, -0.38),
      radius: 0.95,
      colors: [
        Color.lerp(accent, Colors.white, 0.78)!,
        accent,
        Color.lerp(accent, Colors.black, 0.42)!,
      ],
      stops: const [0.0, 0.46, 1.0],
    ).createShader(sphereRect);
  canvas.drawCircle(center, r, spherePaint);

  // 3. Ambient rim bounce light along shadow edge
  final rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = (r * 0.20).clamp(0.6, 1.4)
    ..shader = RadialGradient(
      center: const Alignment(0.45, 0.45),
      radius: 0.75,
      colors: [
        Color.lerp(accent, Colors.white, 0.6)!.withOpacity(0.60),
        Colors.transparent,
      ],
    ).createShader(sphereRect);
  canvas.drawCircle(center, r * 0.90, rimPaint);

  // 4. Primary crisp white specular highlight
  final highlightCenter = Offset(center.dx - r * 0.35, center.dy - r * 0.35);
  canvas.drawOval(
    Rect.fromCenter(center: highlightCenter, width: r * 0.55, height: r * 0.38),
    Paint()..color = Colors.white.withOpacity(0.95),
  );

  // 5. Secondary micro pin-point sparkle
  canvas.drawCircle(
    Offset(center.dx - r * 0.15, center.dy - r * 0.48),
    (r * 0.14).clamp(0.4, 1.0),
    Paint()..color = Colors.white.withOpacity(0.90),
  );
}

class _ReferenceBackground extends StatelessWidget {
  const _ReferenceBackground({required this.accent, required this.time});
  final Color accent;
  final Animation<double> time;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(accent.withOpacity(.05), const Color(0xFFFFF9FD)),
              Colors.white,
              Color.alphaBlend(accent.withOpacity(.06), const Color(0xFFFFF2F9)),
              Color.alphaBlend(accent.withOpacity(.03), const Color(0xFFFFF9FC)),
            ],
            stops: const [0, .35, .72, 1],
          ),
        ),
        child: CustomPaint(
          painter: _SilkWavePainter(accent: accent, time: time),
          size: Size.infinite,
        ),
      );
}

class _SilkWavePainter extends CustomPainter {
  _SilkWavePainter({required this.accent, required this.time})
      : super(repaint: time);

  final Color accent;
  final Animation<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = time.value * math.pi * 2;
    final breathe = math.sin(t) * 6.5;
    final breatheAlt = math.cos(t * 0.9) * 5.5;

    // ── 1. Background Ambient Silk Flow ─────────────────────────
    final baseWavePaint = Paint()..style = PaintingStyle.fill;
    final crestPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    for (int i = 0; i < 4; i++) {
      final y = h * (0.10 + i * 0.19) + math.sin(t + i * 1.3) * 5.0;
      final wavePath = Path()
        ..moveTo(-w * 0.20, y - h * 0.05)
        ..cubicTo(w * 0.20, y - h * 0.12, w * 0.45, y + h * 0.08, w * 0.70, y - h * 0.02)
        ..cubicTo(w * 0.90, y - h * 0.07, w * 1.05, y + h * 0.06, w * 1.25, y - h * 0.01)
        ..lineTo(w * 1.25, y + h * 0.05)
        ..cubicTo(w * 1.05, y + h * 0.12, w * 0.85, y + h * 0.03, w * 0.55, y + h * 0.09)
        ..cubicTo(w * 0.25, y + h * 0.15, w * 0.05, y - h * 0.01, -w * 0.20, y + h * 0.04)
        ..close();

      baseWavePaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.01),
          accent.withOpacity(i.isEven ? 0.20 : 0.10),
          Color.lerp(accent, Colors.white, 0.5)!.withOpacity(0.07),
          Colors.white.withOpacity(0.01),
        ],
      ).createShader(Rect.fromLTWH(0, y - h * 0.12, w, h * 0.24));
      canvas.drawPath(wavePath, baseWavePaint);

      crestPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          accent.withOpacity(0.30),
          Colors.white.withOpacity(0.65),
          accent.withOpacity(0.25),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(-w * 0.20, y - h * 0.10, w * 1.4, h * 0.2));

      final crestPath = Path()
        ..moveTo(-w * 0.20, y - h * 0.05)
        ..cubicTo(w * 0.20, y - h * 0.12, w * 0.45, y + h * 0.08, w * 0.70, y - h * 0.02)
        ..cubicTo(w * 0.90, y - h * 0.07, w * 1.05, y + h * 0.06, w * 1.25, y - h * 0.01);
      canvas.drawPath(crestPath, crestPaint);
    }

    // ── 2. Rich Voluptuous 3D Satin Silk Ribbons (Around the Orb) ───
    // Ribbon A: Sweeping Left Ribbon (from top left down along left waist of orb)
    final leftRibbon = Path()
      ..moveTo(-w * 0.15, h * 0.06 + breathe)
      ..cubicTo(w * 0.06, h * 0.14 + breathe, w * 0.24, h * 0.22 + breathe * 0.8, w * 0.26, h * 0.31 + breathe * 0.5)
      ..cubicTo(w * 0.27, h * 0.39 + breathe * 0.3, w * 0.16, h * 0.46 + breathe * 0.2, -w * 0.15, h * 0.50 + breathe * 0.1)
      ..cubicTo(w * 0.08, h * 0.43, w * 0.16, h * 0.36, w * 0.14, h * 0.26)
      ..cubicTo(w * 0.12, h * 0.16, -w * 0.02, h * 0.11, -w * 0.15, h * 0.06 + breathe)
      ..close();

    // Dark fold shadow under left ribbon
    canvas.drawPath(
      leftRibbon,
      Paint()
        ..color = Color.lerp(accent, Colors.black, 0.45)!.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Left Ribbon gradient: deep velvet to luminous satin highlight
    final leftPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(accent, Colors.black, 0.40)!.withOpacity(0.85),
          accent.withOpacity(0.92),
          Color.lerp(accent, Colors.white, 0.52)!.withOpacity(0.98),
          accent.withOpacity(0.70),
          Color.lerp(accent, Colors.black, 0.50)!.withOpacity(0.82),
        ],
        stops: const [0.0, 0.25, 0.55, 0.80, 1.0],
      ).createShader(Rect.fromLTWH(-w * 0.15, h * 0.06, w * 0.45, h * 0.45));
    canvas.drawPath(leftRibbon, leftPaint);

    // Left Ribbon Satin Ridge Highlight
    final leftRidge = Path()
      ..moveTo(-w * 0.15, h * 0.06 + breathe)
      ..cubicTo(w * 0.06, h * 0.14 + breathe, w * 0.24, h * 0.22 + breathe * 0.8, w * 0.26, h * 0.31 + breathe * 0.5)
      ..cubicTo(w * 0.27, h * 0.39 + breathe * 0.3, w * 0.16, h * 0.46 + breathe * 0.2, -w * 0.15, h * 0.50 + breathe * 0.1);
    canvas.drawPath(
      leftRidge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Color.lerp(accent, Colors.white, 0.7)!.withOpacity(0.9),
            Colors.white.withOpacity(0.95),
            Color.lerp(accent, Colors.white, 0.7)!.withOpacity(0.8),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(-w * 0.15, h * 0.06, w * 0.45, h * 0.45)),
    );

    // Ribbon B: Upper Right Fluid Silk Wave
    final rightRibbon1 = Path()
      ..moveTo(w * 0.60, h * 0.19 + breathe * 0.6)
      ..cubicTo(w * 0.78, h * 0.13 + breathe * 0.8, w * 0.95, h * 0.18 + breathe, w * 1.20, h * 0.24 + breathe)
      ..cubicTo(w * 1.05, h * 0.32 + breathe * 0.8, w * 0.86, h * 0.28 + breathe * 0.5, w * 0.62, h * 0.26 + breathe * 0.4)
      ..cubicTo(w * 0.60, h * 0.24 + breathe * 0.5, w * 0.59, h * 0.21 + breathe * 0.6, w * 0.60, h * 0.19 + breathe * 0.6)
      ..close();

    // Shadow behind right ribbon 1
    canvas.drawPath(
      rightRibbon1,
      Paint()
        ..color = Color.lerp(accent, Colors.black, 0.42)!.withOpacity(0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final rightPaint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.lerp(accent, Colors.white, 0.45)!.withOpacity(0.92),
          accent.withOpacity(0.90),
          Color.lerp(accent, Colors.black, 0.38)!.withOpacity(0.85),
          Color.lerp(accent, Colors.white, 0.30)!.withOpacity(0.75),
        ],
        stops: const [0.0, 0.35, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(w * 0.60, h * 0.13, w * 0.60, h * 0.25));
    canvas.drawPath(rightRibbon1, rightPaint1);

    // Ridge on right ribbon 1
    final rightRidge1 = Path()
      ..moveTo(w * 0.60, h * 0.19 + breathe * 0.6)
      ..cubicTo(w * 0.78, h * 0.13 + breathe * 0.8, w * 0.95, h * 0.18 + breathe, w * 1.20, h * 0.24 + breathe);
    canvas.drawPath(
      rightRidge1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = LinearGradient(
          colors: [
            Color.lerp(accent, Colors.white, 0.8)!.withOpacity(0.9),
            Colors.white.withOpacity(0.98),
            Color.lerp(accent, Colors.white, 0.6)!.withOpacity(0.8),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(w * 0.60, h * 0.13, w * 0.60, h * 0.20)),
    );

    // Ribbon C: Cascading Lower Right Silk Fold
    final rightRibbon2 = Path()
      ..moveTo(w * 0.58, h * 0.29 + breatheAlt * 0.5)
      ..cubicTo(w * 0.76, h * 0.29 + breatheAlt * 0.7, w * 0.94, h * 0.37 + breatheAlt, w * 1.20, h * 0.42 + breatheAlt)
      ..cubicTo(w * 0.98, h * 0.48 + breatheAlt * 0.7, w * 0.78, h * 0.42 + breatheAlt * 0.4, w * 0.56, h * 0.35 + breatheAlt * 0.3)
      ..close();

    canvas.drawPath(
      rightRibbon2,
      Paint()
        ..color = Color.lerp(accent, Colors.black, 0.45)!.withOpacity(0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final rightPaint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withOpacity(0.75),
          Color.lerp(accent, Colors.black, 0.42)!.withOpacity(0.80),
          accent.withOpacity(0.65),
          Color.lerp(accent, Colors.white, 0.55)!.withOpacity(0.85),
        ],
      ).createShader(Rect.fromLTWH(w * 0.56, h * 0.28, w * 0.64, h * 0.24));
    canvas.drawPath(rightRibbon2, rightPaint2);

    final rightRidge2 = Path()
      ..moveTo(w * 0.58, h * 0.29 + breatheAlt * 0.5)
      ..cubicTo(w * 0.76, h * 0.29 + breatheAlt * 0.7, w * 0.94, h * 0.37 + breatheAlt, w * 1.20, h * 0.42 + breatheAlt);
    canvas.drawPath(
      rightRidge2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Color.lerp(accent, Colors.white, 0.75)!.withOpacity(0.85),
            Colors.white.withOpacity(0.95),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(w * 0.58, h * 0.29, w * 0.62, h * 0.15)),
    );

    // ── 3. Floating 3D Liquid Droplets / Pearls ────────────────────
    for (int i = 0; i < _kDroplets.length; i++) {
      final d = _kDroplets[i];
      final bob = math.sin(t * d.speed + d.phase) * (4.5 + (i % 3) * 1.8);
      final center = Offset(w * d.dx, h * d.dy + bob);
      _draw3DDroplet(canvas, center, d.radius, accent);
    }
  }

  @override
  bool shouldRepaint(covariant _SilkWavePainter oldDelegate) => true;
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
  Widget build(BuildContext context) {
    final fontSize = (width * .078).clamp(32.0, 48.0);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // "SIYA" with modern geometric aesthetic & soft ambient glow
            Text(
              'SIYA',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                color: const Color(0xFF0F172A),
                shadows: [
                  Shadow(
                    color: accent.withOpacity(0.40),
                    blurRadius: 14,
                    offset: const Offset(0, 2),
                  ),
                  Shadow(
                    color: Colors.white.withOpacity(0.9),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // "AI" with dynamic glowing accent gradient (Pink/Purple to Neon Cyan)
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent,
                  Color.lerp(accent, const Color(0xFFFF5CF2), 0.6)!,
                  const Color(0xFF00E5FF),
                ],
              ).createShader(bounds),
              child: Text(
                'AI',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  shadows: [
                    Shadow(
                      color: accent.withOpacity(0.50),
                      blurRadius: 16,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Sleek Micro-Sparkle ✨ & Glowing Pulse Dot Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(0.18),
                    const Color(0xFF00E5FF).withOpacity(0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.35), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.8),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    '✨',
                    style: TextStyle(fontSize: 10, height: 1.1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

class _OrbGlassHaloPainter extends CustomPainter {
  const _OrbGlassHaloPainter({
    required this.time,
    required this.level,
    required this.active,
    required this.accent,
  });

  final Animation<double> time;
  final ValueListenable<double> level;
  final bool active;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final lvl = level.value;
    final pulse = (active ? 0.035 : 0.015) * math.sin(time.value * math.pi * 2) + lvl * 0.04;
    final r = size.width * 0.37 * (1.0 + pulse);
    final haloR = r * 1.28;

    // 1. Broad Frosted Glass Drop Shadow on silk background
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..color = Color.lerp(accent, Colors.black, 0.25)!.withOpacity(active ? 0.45 : 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    // 2. Translucent Fluid Glass Ring Band
    final haloPath = Path()
      ..addOval(Rect.fromCircle(center: c, radius: haloR))
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..fillType = PathFillType.evenOdd;

    final glassPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          accent.withOpacity(0.12),
          Color.lerp(accent, Colors.white, 0.6)!.withOpacity(0.24),
          accent.withOpacity(0.08),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: haloR));
    canvas.drawPath(haloPath, glassPaint);

    // 3. Frosted Ambient Outer Blur Aura
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = accent.withOpacity(active ? 0.35 : 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // 4. Specular Glass Bevel Highlight along the top rim arc
    final glassBevel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Color.lerp(accent, Colors.white, 0.8)!.withOpacity(0.7),
          Colors.white.withOpacity(0.95),
          Color.lerp(accent, Colors.white, 0.8)!.withOpacity(0.7),
          Colors.transparent,
        ],
        stops: const [0.0, 0.15, 0.25, 0.35, 0.50],
        transform: const GradientRotation(-math.pi * 0.75),
      ).createShader(Rect.fromCircle(center: c, radius: haloR));

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: haloR),
      -math.pi * 0.85,
      math.pi * 0.70,
      false,
      glassBevel,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbGlassHaloPainter oldDelegate) => true;
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

                // Outer Frosted Glass Aura & Elevated 3D Rim (from image 3)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OrbGlassHaloPainter(
                      time: time,
                      level: level,
                      active: active,
                      accent: accent,
                    ),
                  ),
                ),

                // Center Hologram Orb Core with Dynamic Theme Color & True 3D Aesthetics
                Transform.scale(
                  scale: 1.0 + pulse,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: _HologramOrbCore(
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

class _HologramOrbCore extends StatelessWidget {
  const _HologramOrbCore({
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
        // 1. Deep Glossy Hologram Sphere Base with Dynamic Ambient Glow
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

        // 2. High-Resolution Original Flame Crest, Typography & Underline Crest
        // Dynamically tinted by the theme accent color using BlendMode.hue
        ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(accent, BlendMode.hue),
              child: Image.asset(
                'assets/images/siya_orb.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),

        // 3. Floating dynamic sparks & twinkling stars
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _OrbSparksPainter(time: time, level: level, accent: accent),
            ),
          ),
        ),

        // 4. Intense Glowing Neon Tube Ring with SweepGradient & Layered Gaussian Blur
        Positioned.fill(
          child: CustomPaint(
            painter: _OrbRingPainter(time: time, level: level, accent: accent),
          ),
        ),
      ],
    );
  }
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

    // 1. Layer 1: Wide diffuse outer neon bloom aura
    final wideBloom = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0
      ..color = accent.withOpacity(0.48)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(c, r, wideBloom);

    // 2. Layer 2: Radiant mid neon tube glow
    final midBloom = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..color = Color.lerp(accent, Colors.white, 0.35)!.withOpacity(0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(c, r, midBloom);

    // 3. Layer 3: Rotating SweepGradient neon glass tube
    final tubePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..shader = SweepGradient(
        colors: [
          Color.lerp(accent, Colors.white, 0.85)!,
          accent,
          Color.lerp(accent, Colors.white, 0.35)!,
          Color.lerp(accent, Colors.black, 0.25)!,
          Color.lerp(accent, Colors.white, 0.85)!,
        ],
        stops: const [0.0, 0.32, 0.65, 0.88, 1.0],
        transform: GradientRotation(time.value * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, tubePaint);

    // 4. Layer 4: Sharp white-hot electric core line
    final coreLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withOpacity(0.95)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);
    canvas.drawCircle(c, r, coreLine);
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
