import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/dot_ring.dart';
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
          final ring = math.min(w * 0.79, h * 0.47);
          final titleTop = safeTop + h * 0.018;
          final ringTop = h * 0.185;

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
                        label: '',
                      ),
                    ),
                  ),
                ),
              ),
              // Floating neon navigation with the hologram kept as the central action.
              Positioned(
                left: w * 0.035,
                right: w * 0.035,
                bottom: safeBottom + h * 0.012,
                child: FadeTransition(
                  opacity: _iv(0.35, 0.95, Curves.easeOut),
                  child: _NeonBottomBar(
                    width: w * 0.93,
                    time: _ctrl,
                    active: widget.bridge.isActive,
                    onHome: () {},
                    onChat: () => _showChatUnavailable(context),
                    onOrb: widget.bridge.toggleMic,
                    onFeatures: () => Navigator.of(context).pushNamed('/features'),
                    onSettings: _openSettings,
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


void _showChatUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      content: Text('Chat panel is not available yet. Tap the center hologram for voice.'),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Floating, translucent navigation bar inspired by the supplied neon reference.
/// Colors intentionally reuse Siya's pink/magenta/orange brand palette.
class _NeonBottomBar extends StatelessWidget {
  const _NeonBottomBar({
    required this.width,
    required this.time,
    required this.active,
    required this.onHome,
    required this.onChat,
    required this.onOrb,
    required this.onFeatures,
    required this.onSettings,
  });

  final double width;
  final Animation<double> time;
  final bool active;
  final VoidCallback onHome;
  final VoidCallback onChat;
  final VoidCallback onOrb;
  final VoidCallback onFeatures;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final barHeight = width * 0.285;
    final orbSize = width * 0.265;
    return SizedBox(
      width: width,
      height: barHeight + orbSize * 0.20,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barHeight,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xEE160A2B),
                borderRadius: BorderRadius.circular(barHeight * 0.35),
                border: Border.all(color: const Color(0xAAE85AFF), width: 1.1),
                boxShadow: const [
                  BoxShadow(color: Color(0x557A19FF), blurRadius: 24, spreadRadius: 1),
                  BoxShadow(color: Color(0x33250848), blurRadius: 16, offset: Offset(0, 7)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(child: _NavItem(icon: Icons.home_rounded, active: true, onTap: onHome)),
                  Expanded(child: _NavItem(icon: Icons.chat_bubble_outline_rounded, onTap: onChat)),
                  SizedBox(width: orbSize * 0.93),
                  Expanded(child: _NavItem(icon: Icons.grid_view_rounded, onTap: onFeatures)),
                  Expanded(child: _NavItem(icon: Icons.settings_outlined, onTap: onSettings)),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: AnimatedBuilder(
              animation: time,
              builder: (context, child) => Transform.scale(
                scale: 1 + 0.025 * math.sin(time.value * math.pi * 2),
                child: child,
              ),
              child: GestureDetector(
                onTap: onOrb,
                child: Container(
                  width: orbSize,
                  height: orbSize,
                  padding: EdgeInsets.all(orbSize * 0.06),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xAAFFBDF0),
                    border: Border.all(color: const Color(0xFFFFDDFB), width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x77F52ACB), blurRadius: 24, spreadRadius: 4),
                      BoxShadow(color: Color(0x554B62FF), blurRadius: 22, spreadRadius: 3),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF4518D5), Color(0xFF9D25FF), Color(0xFFEC29D5), Color(0xFF03A9F4)],
                        stops: [0.0, 0.35, 0.72, 1.0],
                      ),
                      border: Border.all(color: Colors.white, width: 1.7),
                    ),
                    child: CustomPaint(painter: _MiniOrbPainter(time: time, active: active)),
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

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.onTap, this.active = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: widthAwareSize(context),
                  color: active ? const Color(0xFFFF61E8) : const Color(0xFFF7F0FF),
                  shadows: active
                      ? const [Shadow(color: Color(0xFFFF27D9), blurRadius: 15)]
                      : const [Shadow(color: Color(0x665F42FF), blurRadius: 8)],
                ),
                if (active)
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 34,
                    height: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF58E6),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Color(0xFFFF2DDF), blurRadius: 10, spreadRadius: 1)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  double widthAwareSize(BuildContext context) => (MediaQuery.sizeOf(context).width * 0.064).clamp(21.0, 28.0);
}

class _MiniOrbPainter extends CustomPainter {
  _MiniOrbPainter({required this.time, required this.active});

  final Animation<double> time;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.36;
    final p = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final angle = time.value * math.pi * 2 * (i.isEven ? 1 : -0.7) + i * math.pi / 2;
      p
        ..strokeWidth = size.width * (active ? 0.075 : 0.045)
        ..color = [const Color(0xFFFF7AF0), const Color(0xFF42D9FF), const Color(0xFFC8A2FF), const Color(0xFFFF9CDE)][i]
            .withOpacity(active ? 0.9 : 0.7);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * (0.68 + i * 0.095)),
        angle,
        math.pi * (0.48 + (active ? 0.08 : 0.0)),
        false,
        p,
      );
    }
    final glow = Paint()..color = Colors.white.withOpacity(0.9);
    canvas.drawCircle(center, size.width * 0.035, glow);
  }

  @override
  bool shouldRepaint(covariant _MiniOrbPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.active != active;
}
