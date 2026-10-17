import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/dot_ring.dart';
import '../widgets/glass_button.dart';
import '../widgets/siya_orb_button.dart';
import '../widgets/wallpaper_layer.dart';
import 'settings_screen.dart';

/// Siya home screen with a compact Aurora floating action pill.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctrl; // saari animations ki ek hi ghadi
  late final AnimationController _intro;
  final ValueNotifier<double> _level = ValueNotifier<double>(0.12);

  String _wpType = 'none';
  String _wpPath = '';
  bool _wpSound = false;
  double _wpDim = 0.35;

  Future<void> _loadWallpaper() async {
    try {
      final s = await widget.bridge.getSettings();
      if (!mounted) return;
      setState(() {
        _wpType = (s['wallpaper_type'] as String?) ?? 'none';
        _wpPath = (s['wallpaper_path'] as String?) ?? '';
        _wpSound = (s['wallpaper_sound'] as bool?) ?? false;
        _wpDim = ((s['wallpaper_dim'] as num?) ?? 0.35).toDouble();
      });
    } catch (_) {}
  }

  Animation<double> _iv(double a, double b, Curve c) => CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
    _ctrl.addListener(_tick);
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..forward();
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

  /// App background mein ho to animation band (battery + CPU bachta hai, phone garam nahi hota).
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
        backgroundColor: SiyaColors.card,
        action: code == 'no_key' ? SnackBarAction(label: 'Settings', textColor: SiyaLight.orangeSoft, onPressed: _openSettings) : null,
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
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(bridge: widget.bridge)));
    _loadWallpaper();
  }

  String _ringLabel(String s) => switch (s) {
        'listening' => "I'm listening",
        'speaking' => 'Speaking...',
        'processing' => 'Thinking...',
        'waiting' => 'Connecting...',
        _ => 'Tap to talk',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SiyaColors.bg,
      body: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final ring = w * 0.64;

        return Stack(
          children: [
            const Positioned.fill(child: AuroraBackground()),
            Positioned.fill(child: WallpaperLayer(type: _wpType, path: _wpPath, sound: _wpSound, dim: _wpDim)),

            // title "Siya Ai ✦"
            Positioned(
              top: h * 0.062,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _iv(0.05, 0.55, Curves.easeOut),
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(_iv(0.05, 0.6, Curves.easeOutCubic)),
                  child: Center(child: _Title(width: w)),
                ),
              ),
            ),

            // settings
            Positioned(
              top: h * 0.056,
              right: w * 0.045,
              child: FadeTransition(
                opacity: _iv(0.25, 0.7, Curves.easeOut),
                child: GlassButton(size: w * 0.105, icon: Icons.settings_rounded, onTap: _openSettings),
              ),
            ),

            // dotted ring + gola
            Positioned(
              left: (w - ring) / 2,
              top: h * 0.385 - ring / 2,
              width: ring,
              height: ring,
              child: FadeTransition(
                opacity: _iv(0.0, 0.6, Curves.easeOut),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.6, end: 1).animate(_iv(0.0, 0.85, Curves.easeOutBack)),
                  child: AnimatedBuilder(
                    animation: widget.bridge,
                    builder: (_, __) => DotRing(size: ring, time: _ctrl, level: _level, label: _ringLabel(widget.bridge.state)),
                  ),
                ),
              ),
            ),

            // greeting / status text
            Positioned(
              top: h * 0.645,
              left: w * 0.08,
              right: w * 0.08,
              child: FadeTransition(
                opacity: _iv(0.3, 0.8, Curves.easeOut),
                child: AnimatedBuilder(
                  animation: widget.bridge,
                  builder: (_, __) => _Greeting(width: w, status: widget.bridge.state == 'idle' ? '' : widget.bridge.status),
                ),
              ),
            ),

            // Compact floating activator; satellite actions expand on demand.
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: FadeTransition(
                opacity: _iv(0.35, 0.85, Curves.easeOut),
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.7), end: Offset.zero).animate(_iv(0.35, 1.0, Curves.easeOutCubic)),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: widget.bridge,
                      builder: (_, __) => SiyaOrbButton(
                        time: _ctrl,
                        isActive: widget.bridge.isActive,
                        micMuted: widget.bridge.micMuted,
                        onMicTap: widget.bridge.toggleMicMute,
                        onMinimize: widget.bridge.minimizeApp,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final fs = width * 0.092;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Siya Ai',
          style: TextStyle(
            color: Colors.white,
            fontSize: fs,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
            height: 1.1,
            shadows: const [Shadow(color: Color(0x33C2185B), blurRadius: 10)],
          ),
        ),
        SizedBox(width: width * 0.012),
        Padding(
          padding: EdgeInsets.only(top: width * 0.004),
          child: SizedBox(width: width * 0.075, height: width * 0.075, child: const CustomPaint(painter: _SparklesPainter())),
        ),
      ],
    );
  }
}

/// Design ke upar-right ke do chhote sparkle (bada + chhota).
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
    final p = Paint()..color = Colors.white.withOpacity(0.92);
    _star(canvas, Offset(s.width * 0.55, s.height * 0.5), s.width * 0.42, p);
    _star(canvas, Offset(s.width * 0.18, s.height * 0.14), s.width * 0.16, p);
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
              style: TextStyle(color: SiyaLight.ink, fontSize: big, fontWeight: FontWeight.w500, height: 1.4),
            )
          : Column(
              key: const ValueKey('greeting'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hey there! \u{1F44B} How\u2019s your day going?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SiyaLight.ink, fontSize: big, fontWeight: FontWeight.w600, height: 1.35),
                ),
                SizedBox(height: width * 0.008),
                Text(
                  'Want me to play some relaxing music or help you plan your schedule?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SiyaLight.grey, fontSize: big, fontWeight: FontWeight.w400, height: 1.35),
                ),
              ],
            ),
    );
  }
}
