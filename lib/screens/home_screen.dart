import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/dot_ring.dart';
import '../widgets/glass_button.dart';
import '../widgets/wallpaper_layer.dart';
import 'settings_screen.dart';

/// Siya AI home screen matching the supplied pastel pink/orange reference.
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
  final ValueNotifier<double> _level = ValueNotifier<double>(0.12);

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
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
    widget.bridge.listen();
    widget.bridge.error.addListener(_onError);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.bridge.init();
      _loadWallpaper();
      if (await widget.bridge.consumeFirstRun()) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await widget.bridge.requestPermissions();
      }
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
            ? SnackBarAction(label: 'Settings', textColor: Colors.white, onPressed: _openSettings)
            : null,
      ));
  }

  void _tick() {
    final b = widget.bridge;
    double target;
    switch (b.state) {
      case 'listening':
        target = 0.30 + 0.70 * b.amp.value;
        break;
      case 'speaking':
        target = 0.55 + 0.45 * math.sin(_ctrl.value * math.pi * 2 * 36).abs();
        break;
      case 'processing':
      case 'waiting':
        target = 0.45;
        break;
      default:
        target = 0.10;
    }
    _level.value += (target - _level.value) * 0.12;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.bridge.error.removeListener(_onError);
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
    _intro.dispose();
    _level.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(bridge: widget.bridge)),
    );
    _loadWallpaper();
  }

  String _ringLabel(String s) => switch (s) {
        'listening' => "I’m listening",
        'speaking' => 'Speaking...',
        'processing' => 'Thinking...',
        'waiting' => 'Connecting...',
        _ => 'Tap the glow below',
      };

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFEAF4),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFFEAF4),
        body: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final safeTop = MediaQuery.of(context).padding.top;
          final safeBottom = MediaQuery.of(context).padding.bottom;
          final ring = math.min(w * 0.70, h * 0.40);
          final titleTop = safeTop + h * 0.025;
          final ringTop = h * 0.19;
          final greetingTop = h * 0.635;

          return Stack(
            fit: StackFit.expand,
            children: [
              const _PastelHomeBackground(),
              Positioned.fill(
                child: WallpaperLayer(type: _wpType, path: _wpPath, sound: _wpSound, dim: _wpDim),
              ),
              // Header
              Positioned(
                top: titleTop,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _iv(0.0, 0.65, Curves.easeOut),
                  child: Center(child: _Title(width: w)),
                ),
              ),
              Positioned(
                top: safeTop + h * 0.028,
                right: w * 0.065,
                child: FadeTransition(
                  opacity: _iv(0.12, 0.72, Curves.easeOut),
                  child: GlassButton(
                    size: w * 0.125,
                    icon: Icons.settings_rounded,
                    iconColor: const Color(0xFFC21870),
                    onTap: _openSettings,
                  ),
                ),
              ),
              // Central pink glow + animated particles
              Positioned(
                top: ringTop,
                left: (w - ring) / 2,
                width: ring,
                height: ring,
                child: FadeTransition(
                  opacity: _iv(0.0, 0.7, Curves.easeOut),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.82, end: 1).animate(_iv(0.0, 0.8, Curves.easeOutBack)),
                    child: AnimatedBuilder(
                      animation: widget.bridge,
                      builder: (_, __) => DotRing(
                        size: ring,
                        time: _ctrl,
                        level: _level,
                        label: _ringLabel(widget.bridge.state),
                      ),
                    ),
                  ),
                ),
              ),
              // Greeting and subtitle
              Positioned(
                top: greetingTop,
                left: w * 0.075,
                right: w * 0.075,
                child: FadeTransition(
                  opacity: _iv(0.22, 0.8, Curves.easeOut),
                  child: AnimatedBuilder(
                    animation: widget.bridge,
                    builder: (_, __) => _Greeting(
                      width: w,
                      status: widget.bridge.state == 'idle' ? '' : widget.bridge.status,
                    ),
                  ),
                ),
              ),
              // Three controls matching the reference: mic, glowing action, close/minimize.
              Positioned(
                left: w * 0.105,
                right: w * 0.105,
                bottom: safeBottom + h * 0.035,
                child: FadeTransition(
                  opacity: _iv(0.35, 0.95, Curves.easeOut),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _RoundControl(
                        size: w * 0.135,
                        icon: widget.bridge.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        onTap: widget.bridge.toggleMicMute,
                      ),
                      _MainGlowButton(
                        size: w * 0.235,
                        time: _ctrl,
                        active: widget.bridge.isActive,
                        onTap: widget.bridge.toggleMic,
                      ),
                      _RoundControl(
                        size: w * 0.135,
                        icon: Icons.close_rounded,
                        onTap: widget.bridge.minimizeApp,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _PastelHomeBackground extends StatelessWidget {
  const _PastelHomeBackground();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFA45E),
              Color(0xFFFFB9D9),
              Color(0xFFFFFBFF),
              Color(0xFFFFDCEB),
              Color(0xFFE84BFF),
            ],
            stops: [0.0, 0.22, 0.48, 0.73, 1.0],
          ),
        ),
        child: CustomPaint(painter: _PastelGlowPainter(), size: Size.infinite),
      );
}

class _PastelGlowPainter extends CustomPainter {
  const _PastelGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glows = <(Offset, double, Color)>[
      (Offset(size.width * 0.06, size.height * 0.04), size.width * 0.75, const Color(0xFFFF9C4B)),
      (Offset(size.width * 0.98, size.height * 0.05), size.width * 0.70, const Color(0xFFE52BFF)),
      (Offset(size.width * 0.08, size.height * 0.98), size.width * 0.65, const Color(0xFFFF9A35)),
      (Offset(size.width * 0.92, size.height * 0.94), size.width * 0.78, const Color(0xFFEA16F4)),
    ];
    for (final (center, radius, color) in glows) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withOpacity(0.72), color.withOpacity(0.25), color.withOpacity(0.0)],
            stops: const [0.0, 0.48, 1.0],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Title extends StatelessWidget {
  const _Title({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Siya Ai',
            style: TextStyle(
              color: Colors.white,
              fontSize: width * 0.074,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.4,
              height: 1.1,
              shadows: const [Shadow(color: Color(0x55D41D9C), blurRadius: 12)],
            ),
          ),
          SizedBox(width: width * 0.012),
          CustomPaint(
            size: Size(width * 0.055, width * 0.055),
            painter: const _SparklesPainter(),
          ),
        ],
      );
}

class _SparklesPainter extends CustomPainter {
  const _SparklesPainter();

  void _star(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final rad = i.isEven ? r : r * 0.2;
      final o = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white.withOpacity(0.96);
    _star(canvas, Offset(s.width * 0.58, s.height * 0.55), s.width * 0.43, p);
    _star(canvas, Offset(s.width * 0.18, s.height * 0.14), s.width * 0.17, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.width, required this.status});
  final double width;
  final String status;

  @override
  Widget build(BuildContext context) {
    final big = width * 0.043;
    final live = status.trim().isNotEmpty;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: live
          ? Text(
              status,
              key: ValueKey(status),
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF0F172A), fontSize: big, fontWeight: FontWeight.w500, height: 1.35),
            )
          : Column(
              key: const ValueKey('greeting'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hey there! 👋 How’s your day going?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: const Color(0xFF0F172A), fontSize: big, fontWeight: FontWeight.w600, height: 1.35),
                ),
                SizedBox(height: width * 0.008),
                Text(
                  'Want me to play some relaxing music or help you plan your schedule?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: const Color(0xFF8790A0), fontSize: big, fontWeight: FontWeight.w400, height: 1.35),
                ),
              ],
            ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({required this.size, required this.icon, required this.onTap});
  final double size;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withOpacity(0.42),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.32)),
            ),
            child: Icon(icon, size: size * 0.44, color: const Color(0xFFC21870)),
          ),
        ),
      );
}

class _MainGlowButton extends StatelessWidget {
  const _MainGlowButton({required this.size, required this.time, required this.active, required this.onTap});
  final double size;
  final Animation<double> time;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: time,
        builder: (context, child) {
          final pulse = 1 + 0.025 * math.sin(time.value * math.pi * 2);
          return Transform.scale(scale: pulse, child: child);
        },
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.055),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.18),
              border: Border.all(color: Colors.white.withOpacity(0.48), width: 1.5),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFF47C9).withOpacity(0.25), blurRadius: 25, spreadRadius: 6),
                BoxShadow(color: const Color(0xFFFFA45E).withOpacity(0.18), blurRadius: 18, spreadRadius: 2),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE900FF), Color(0xFFFC38B7), Color(0xFFFF8A42), Color(0xFFEA21FF)],
                  stops: [0.0, 0.38, 0.7, 1.0],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                boxShadow: const [BoxShadow(color: Color(0x66FF4CCF), blurRadius: 15, spreadRadius: 1)],
              ),
              child: Center(
                child: Icon(
                  active ? Icons.graphic_eq_rounded : Icons.power_settings_new_rounded,
                  color: Colors.white,
                  size: size * 0.40,
                  shadows: const [Shadow(color: Colors.white, blurRadius: 16)],
                ),
              ),
            ),
          ),
        ),
      );
}
