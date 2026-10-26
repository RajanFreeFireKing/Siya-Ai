import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/dot_ring.dart';
import '../widgets/wallpaper_layer.dart';
import '../widgets/wave_painter.dart';
import 'settings_screen.dart';

/// Siya AI home screen inspired by the supplied pink-glass reference.
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
  final TextEditingController _message = TextEditingController();
  final FocusNode _messageFocus = FocusNode();

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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(bridge: widget.bridge)),
    );
    _loadWallpaper();
  }

  Future<void> _sendMessage() async {
    if (_message.text.trim().isEmpty) return;
    _message.clear();
    _messageFocus.unfocus();
    // Text-chat requests are not yet exposed by the current native bridge.
    // Explain the available voice path instead of implying a text request was sent.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Text chat bridge abhi connected nahi hai. Voice ke liye center mic tap karein.'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFFFFF7FB),
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF7FB),
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final safeBottom = MediaQuery.of(context).viewInsets.bottom > 0
              ? 10.0
              : MediaQuery.of(context).padding.bottom;
          final compact = h < 730;
          final ring = math.min(w * 0.72, h * (compact ? 0.30 : 0.335));
          return Stack(
            fit: StackFit.expand,
            children: [
              const _ReferenceBackground(),
              Positioned.fill(
                child: IgnorePointer(
                  child: WallpaperLayer(type: _wpType, path: _wpPath, sound: _wpSound, dim: _wpDim),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(w * 0.065, 6, w * 0.055, 0),
                      child: Row(
                        children: [
                          Expanded(child: Align(alignment: Alignment.centerLeft, child: _BrandTitle(width: w))),
                          _NotificationButton(onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Abhi koi nayi notification nahi hai.'),
                              behavior: SnackBarBehavior.floating,
                            ));
                          }),
                        ],
                      ),
                    ),
                    SizedBox(height: h * (compact ? 0.012 : 0.022)),
                    FadeTransition(
                      opacity: _iv(0.05, 0.72, Curves.easeOut),
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.88, end: 1).animate(_iv(0.02, 0.8, Curves.easeOutBack)),
                        child: SizedBox(
                          width: ring,
                          height: ring,
                          child: AnimatedBuilder(
                            animation: widget.bridge,
                            builder: (_, __) => _CoreLogo(
                              size: ring,
                              time: _ctrl,
                              level: _level,
                              active: widget.bridge.isActive,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: h * (compact ? 0.010 : 0.018)),
                    Text(
                      _greeting,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF09090F),
                        fontSize: (w * 0.078).clamp(26.0, 36.0),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        _subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF596071),
                          fontSize: (w * 0.045).clamp(15.0, 20.0),
                          letterSpacing: -.35,
                        ),
                      ),
                    ),
                    SizedBox(height: h * (compact ? 0.012 : 0.020)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * .075),
                      child: Container(
                        height: compact ? 60 : 78,
                        decoration: BoxDecoration(
                          color: const Color(0x44FFFFFF),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: const [BoxShadow(color: Color(0x22FF6EA9), blurRadius: 22, spreadRadius: 2)],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: AnimatedBuilder(
                          animation: _ctrl,
                          builder: (_, __) => CustomPaint(
                            painter: SiyaWavePainter(time: _ctrl, level: _level, active: widget.bridge.isActive),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: h * (compact ? 0.012 : 0.022)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * .05),
                      child: _MessageBox(
                        controller: _message,
                        focusNode: _messageFocus,
                        onSend: _sendMessage,
                        onAttach: () async {
                          try {
                            final path = await widget.bridge.pickMedia('image');
                            if (mounted && path != null && path.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Image select ho gayi.'),
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          } catch (_) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Image picker abhi available nahi hai.'),
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          }
                        },
                      ),
                    ),
                    const Spacer(),
                    if (MediaQuery.viewInsetsOf(context).bottom == 0)
                      Padding(
                        padding: EdgeInsets.fromLTRB(w * .035, 0, w * .035, math.max(8, safeBottom * .3)),
                        child: FadeTransition(
                          opacity: _iv(.25, 1, Curves.easeOut),
                          child: _ReferenceBottomBar(
                            width: w * .93,
                            time: _ctrl,
                            active: widget.bridge.isActive,
                            onHome: () {},
                            onChat: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Voice mode ke liye center mic tap karein.'),
                              behavior: SnackBarBehavior.floating,
                            )),
                            onMic: widget.bridge.toggleMic,
                            onFeatures: () => Navigator.of(context).pushNamed('/features'),
                            onSettings: _openSettings,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
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

class _ReferenceBackground extends StatelessWidget {
  const _ReferenceBackground();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8FC), Color(0xFFFFFFFF), Color(0xFFFFF2F9), Color(0xFFFFF9FC)],
            stops: [0, .42, .78, 1],
          ),
        ),
        child: CustomPaint(painter: _SilkWavePainter(), size: Size.infinite),
      );
}

class _SilkWavePainter extends CustomPainter {
  const _SilkWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 5; i++) {
      final y = size.height * (.14 + i * .17);
      final path = Path()
        ..moveTo(-size.width * .12, y - size.height * .11)
        ..cubicTo(size.width * .24, y - size.height * .22, size.width * .39, y + size.height * .12, size.width * .68, y)
        ..cubicTo(size.width * .89, y - size.height * .10, size.width * .95, y + size.height * .11, size.width * 1.12, y - size.height * .035)
        ..lineTo(size.width * 1.12, y + size.height * .035)
        ..cubicTo(size.width * .84, y + size.height * .20, size.width * .70, y + size.height * .07, size.width * .43, y + size.height * .11)
        ..cubicTo(size.width * .19, y + size.height * .16, size.width * .06, y - size.height * .04, -size.width * .12, y + size.height * .045)
        ..close();
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0x00FF5AA7),
          Color(0x44FF7DAF).withOpacity(i.isEven ? .24 : .13),
          const Color(0x22F6A7FF),
          const Color(0x00FF5AA7),
        ],
      ).createShader(Rect.fromLTWH(0, y - size.height * .20, size.width, size.height * .40));
      canvas.drawPath(path, paint);
    }
    const normalizedDots = <Offset>[
      Offset(.06, .14), Offset(.16, .22), Offset(.22, .28), Offset(.64, .17),
      Offset(.82, .16), Offset(.88, .25), Offset(.14, .46), Offset(.81, .42),
      Offset(.75, .60), Offset(.29, .73),
    ];
    for (int i = 0; i < normalizedDots.length; i++) {
      final dot = Offset(size.width * normalizedDots[i].dx, size.height * normalizedDots[i].dy);
      final r = size.width * (i % 3 == 0 ? .011 : .007);
      canvas.drawCircle(dot, r * 2.2, Paint()..color = const Color(0x33FF176B)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(dot, r, Paint()..shader = RadialGradient(
        colors: const [Color(0xFFFF9ECA), Color(0xFFE80046)],
      ).createShader(Rect.fromCircle(center: dot, radius: r)));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('SIYA', style: TextStyle(
                fontSize: (width * .075).clamp(28.0, 38.0),
                height: .96, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                letterSpacing: -2, color: const Color(0xFF08070D),
                shadows: const [Shadow(color: Color(0x44FF649B), blurRadius: 8)],
              )),
              const SizedBox(width: 7),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFF003D), Color(0xFFE60077)]).createShader(r),
                child: Text('AI', style: TextStyle(
                  fontSize: (width * .086).clamp(31.0, 42.0), height: .92,
                  fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1.8,
                )),
              ),
            ]),
            SizedBox(height: width * .012),
            Container(
              height: 3, width: width * .30,
              decoration: const BoxDecoration(gradient: LinearGradient(
                colors: [Color(0xFFED0044), Color(0xFFFF4E9C), Colors.transparent],
              )),
            ),
          ],
        ),
      );
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withOpacity(.87),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 58, height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFFE1ED)),
              boxShadow: const [BoxShadow(color: Color(0x22FF3C83), blurRadius: 20, spreadRadius: 2)],
            ),
            child: Stack(alignment: Alignment.center, children: [
              const Icon(Icons.notifications_none_rounded, color: Color(0xFF111118), size: 30),
              Positioned(right: 13, top: 11, child: Container(
                width: 9, height: 9,
                decoration: const BoxDecoration(color: Color(0xFFE50035), shape: BoxShape.circle),
              )),
            ]),
          ),
        ),
      );
}

class _CoreLogo extends StatelessWidget {
  const _CoreLogo({required this.size, required this.time, required this.level, required this.active});
  final double size;
  final Animation<double> time;
  final ValueListenable<double> level;
  final bool active;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: const Color(0xFF080207),
              border: Border.all(color: const Color(0xFFFF5B99), width: 2.5),
              boxShadow: const [
                BoxShadow(color: Color(0x77FF004C), blurRadius: 30, spreadRadius: 4),
                BoxShadow(color: Color(0x44FF6AB6), blurRadius: 10, spreadRadius: 1),
              ],
            ),
          ),
          Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _OrbSparksPainter(time: time, level: level)))),
          Positioned(
            top: size * .19, left: size * .16, right: size * .16, bottom: size * .22,
            child: CustomPaint(painter: _SiyaGlyphPainter(time: time, active: active)),
          ),
          Positioned(
            bottom: size * .19,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('SIYA', style: TextStyle(color: Colors.white, fontSize: size * .092, fontWeight: FontWeight.w800, letterSpacing: -1)),
                const SizedBox(width: 5),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFF174F), Color(0xFFFF00A0)]).createShader(r),
                  child: Text('AI', style: TextStyle(color: Colors.white, fontSize: size * .092, fontWeight: FontWeight.w900, letterSpacing: -.8)),
                ),
              ]),
            ),
          ),
          Positioned(bottom: size * .135, child: Container(
            width: size * .30, height: 1.5,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Color(0xFFFF1B67), Colors.transparent])),
          )),
          Positioned.fill(child: CustomPaint(painter: _OrbRingPainter(time: time, level: level))),
        ],
      );
}

class _SiyaGlyphPainter extends CustomPainter {
  _SiyaGlyphPainter({required this.time, required this.active});
  final Animation<double> time;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .72, size.height * .08)
      ..cubicTo(size.width * .61, size.height * .32, size.width * .34, size.height * .31, size.width * .32, size.height * .50)
      ..cubicTo(size.width * .29, size.height * .66, size.width * .62, size.height * .67, size.width * .70, size.height * .82)
      ..cubicTo(size.width * .78, size.height * .96, size.width * .45, size.height * 1.02, size.width * .23, size.height * .84);
    p.shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFFFFB6D3), Color(0xFFFF174F), Color(0xFFFF00A6)],
      stops: [0, .50, 1],
    ).createShader(Offset.zero & size);
    p.strokeWidth = size.width * .16;
    canvas.drawPath(path, p..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    p.maskFilter = null;
    canvas.drawPath(path, p);
    final c = Offset(size.width * .73, size.height * .40);
    final radius = size.width * (.09 + (active ? .012 : .005) * math.sin(time.value * math.pi * 2));
    final star = Path();
    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final r = i.isEven ? radius : radius * .20;
      final point = Offset(c.dx + math.cos(angle) * r, c.dy + math.sin(angle) * r);
      if (i == 0) { star.moveTo(point.dx, point.dy); } else { star.lineTo(point.dx, point.dy); }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFFFF5FA));
  }

  @override
  bool shouldRepaint(covariant _SiyaGlyphPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.active != active;
}

class _OrbSparksPainter extends CustomPainter {
  _OrbSparksPainter({required this.time, required this.level}) : super(repaint: Listenable.merge([time, level]));
  final Animation<double> time;
  final ValueListenable<double> level;

  static const List<Offset> _points = [
    Offset(.20, .31), Offset(.31, .25), Offset(.79, .25), Offset(.69, .72),
    Offset(.17, .65), Offset(.83, .62), Offset(.39, .80), Offset(.57, .17),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _points.length; i++) {
      final q = _points[i];
      final pulse = .5 + .5 * math.sin(time.value * math.pi * 2 * (i + 1) + i);
      final o = Offset(size.width * q.dx, size.height * q.dy);
      final r = size.width * (.004 + .006 * pulse + level.value * .003);
      canvas.drawCircle(o, r * 3, Paint()..color = const Color(0x55FF174F)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(o, r, Paint()..color = Color.lerp(const Color(0xFFFF334F), Colors.white, pulse * .42)!);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbSparksPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.level != level;
}

class _OrbRingPainter extends CustomPainter {
  _OrbRingPainter({required this.time, required this.level}) : super(repaint: Listenable.merge([time, level]));
  final Animation<double> time;
  final ValueListenable<double> level;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.stroke;
    canvas.drawCircle(size.center(Offset.zero), size.width * (.485 + .004 * math.sin(time.value * math.pi * 4)),
        p..strokeWidth = 2.1..color = const Color(0xAAFF356F));
    canvas.drawCircle(size.center(Offset.zero), size.width * .505, p..strokeWidth = 1.4..color = const Color(0x99FFFFFF));
    canvas.drawCircle(size.center(Offset.zero), size.width * .525, p..strokeWidth = 1..color = const Color(0x55FFB0D2));
  }

  @override
  bool shouldRepaint(covariant _OrbRingPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.level != level;
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.controller, required this.focusNode, required this.onSend, required this.onAttach});
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) => Container(
        height: 70,
        padding: const EdgeInsets.only(left: 8, right: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.93),
          borderRadius: BorderRadius.circular(38),
          border: Border.all(color: const Color(0xFFFFE0EA)),
          boxShadow: const [
            BoxShadow(color: Color(0x22FF2D75), blurRadius: 24, spreadRadius: 1, offset: Offset(0, 8)),
            BoxShadow(color: Color(0xCCFFFFFF), blurRadius: 6, spreadRadius: -2),
          ],
        ),
        child: Row(children: [
          IconButton(
            tooltip: 'Attach image',
            onPressed: onAttach,
            icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF687080), size: 27),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: Color(0xFF161923), fontSize: 17),
              cursorColor: const Color(0xFFE90046),
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Color(0xFF687080), fontSize: 17, letterSpacing: -.35),
                border: InputBorder.none, isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Material(
            color: const Color(0xFFE90036), shape: const CircleBorder(), elevation: 5,
            shadowColor: const Color(0x77FF004C),
            child: InkWell(
              customBorder: const CircleBorder(), onTap: onSend,
              child: const SizedBox(width: 52, height: 52, child: Center(
                child: Icon(Icons.send_rounded, color: Colors.white, size: 27),
              )),
            ),
          ),
        ]),
      );
}

class _ReferenceBottomBar extends StatelessWidget {
  const _ReferenceBottomBar({
    required this.width, required this.time, required this.active, required this.onHome,
    required this.onChat, required this.onMic, required this.onFeatures, required this.onSettings,
  });
  final double width;
  final Animation<double> time;
  final bool active;
  final VoidCallback onHome;
  final VoidCallback onChat;
  final VoidCallback onMic;
  final VoidCallback onFeatures;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final barHeight = (width * .185).clamp(74.0, 108.0);
    final micSize = (width * .225).clamp(88.0, 126.0);
    return SizedBox(
      height: barHeight + micSize * .46,
      child: Stack(
        clipBehavior: Clip.none, alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0, right: 0, bottom: micSize * .17, height: barHeight,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xDDFCE8F2),
                borderRadius: BorderRadius.circular(barHeight * .46),
                border: Border.all(color: const Color(0x99FFFFFF), width: 1.6),
                boxShadow: const [
                  BoxShadow(color: Color(0x33FF3F86), blurRadius: 24, spreadRadius: 1),
                  BoxShadow(color: Color(0xCCFFFFFF), blurRadius: 8, spreadRadius: -2),
                ],
              ),
              child: Row(children: [
                Expanded(child: _ReferenceNavItem(icon: Icons.home_rounded, active: true, onTap: onHome)),
                Expanded(child: _ReferenceNavItem(icon: Icons.chat_bubble_outline_rounded, onTap: onChat)),
                SizedBox(width: micSize * .86),
                Expanded(child: _ReferenceNavItem(icon: Icons.bolt_rounded, onTap: onFeatures)),
                Expanded(child: _ReferenceNavItem(icon: Icons.settings_outlined, onTap: onSettings)),
              ]),
            ),
          ),
          Positioned(
            top: 0,
            child: AnimatedBuilder(
              animation: time,
              builder: (context, child) => Transform.scale(scale: 1 + .018 * math.sin(time.value * math.pi * 2), child: child),
              child: Semantics(
                button: true, label: active ? 'Stop Siya AI voice' : 'Start Siya AI voice',
                child: Material(
                  color: const Color(0xFFFFF7FB), shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(), onTap: onMic,
                    child: Container(
                      width: micSize, height: micSize, padding: EdgeInsets.all(micSize * .07),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Color(0x99FF1B67), blurRadius: 25, spreadRadius: 3),
                          BoxShadow(color: Color(0x66FF84B4), blurRadius: 12, spreadRadius: 1),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(colors: [Color(0xFF020207), Color(0xFF1B0009), Color(0xFFE80046)], stops: [0, .72, 1]),
                          border: Border.all(color: const Color(0xFFFF5C9B), width: 2.4),
                          boxShadow: const [BoxShadow(color: Color(0x77FF003C), blurRadius: 18, spreadRadius: 2)],
                        ),
                        child: Icon(active ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                          color: Colors.white, size: micSize * .37,
                          shadows: const [Shadow(color: Color(0xFFFF1758), blurRadius: 14)]),
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

class _ReferenceNavItem extends StatelessWidget {
  const _ReferenceNavItem({required this.icon, required this.onTap, this.active = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(32),
          child: Center(
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? const Color(0xFFFFF5FA) : const Color(0x22FF2B6C),
                border: Border.all(color: active ? const Color(0x88FFB4CE) : const Color(0x44FFFFFF)),
                boxShadow: active ? const [BoxShadow(color: Color(0x44FF205C), blurRadius: 14, spreadRadius: 1)] : const [],
              ),
              child: Icon(icon, size: 30, color: const Color(0xFFDF0048),
                shadows: const [Shadow(color: Color(0x55FF246E), blurRadius: 10)]),
            ),
          ),
        ),
      );
}
