import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_bottom_navigation.dart';

import 'ai_boss_screen.dart';
import 'permissions_screen.dart';
import 'power_screen.dart';
import 'location_screen.dart';
import 'memory_screen.dart';
import 'profile_screen.dart';
import 'wallpaper_screen.dart';

class _SettingsSilkBackground extends StatelessWidget {
  const _SettingsSilkBackground({super.key, required this.primaryThemeColor});
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
              stops: [0, .40, .78, 1],
            ),
          ),
          child: CustomPaint(
            painter: _SettingsSilkPainter(primaryThemeColor),
            size: Size.infinite,
          ),
        ),
      );
}

class _SettingsSilkPainter extends CustomPainter {
  const _SettingsSilkPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withOpacity(.13),
          accent.withOpacity(.035),
          Colors.transparent,
        ],
        stops: const [0, .55, 1],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .83, size.height * .32),
          radius: size.width * .76,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    final ribbonPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 7; i++) {
      final y = size.height * (.035 + i * .158);
      final ribbon = Path()
        ..moveTo(-size.width * .12, y)
        ..cubicTo(
          size.width * .16, y - size.height * .15,
          size.width * .36, y + size.height * .13,
          size.width * .65, y - size.height * .025,
        )
        ..cubicTo(
          size.width * .86, y - size.height * .10,
          size.width * .97, y + size.height * .095,
          size.width * 1.12, y + size.height * .012,
        )
        ..lineTo(size.width * 1.12, y + size.height * .045)
        ..cubicTo(
          size.width * .86, y + size.height * .17,
          size.width * .66, y + size.height * .055,
          size.width * .40, y + size.height * .12,
        )
        ..cubicTo(
          size.width * .16, y + size.height * .17,
          size.width * .035, y + size.height * .025,
          -size.width * .12, y + size.height * .065,
        )
        ..close();

      ribbonPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(.02),
          accent.withOpacity(i.isEven ? .17 : .085),
          const Color(0xFFFF6EB0).withOpacity(.075),
          Colors.white.withOpacity(.02),
        ],
      ).createShader(
        Rect.fromLTWH(0, y - size.height * .18, size.width, size.height * .36),
      );
      canvas.drawPath(ribbon, ribbonPaint);

      final highlightPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withOpacity(.12);
      final highlight = Path()
        ..moveTo(-size.width * .08, y + size.height * .034)
        ..cubicTo(
          size.width * .20, y - size.height * .08,
          size.width * .47, y + size.height * .19,
          size.width * .76, y + size.height * .025,
        )
        ..cubicTo(
          size.width * .90, y - size.height * .04,
          size.width, y + size.height * .11,
          size.width * 1.08, y + size.height * .05,
        );
      canvas.drawPath(highlight, highlightPaint);
    }

    const points = <Offset>[
      Offset(.68, .04),
      Offset(.78, .09),
      Offset(.59, .15),
      Offset(.92, .20),
      Offset(.12, .34),
      Offset(.88, .47),
      Offset(.15, .64),
      Offset(.80, .76),
      Offset(.07, .91),
      Offset(.94, .89),
      Offset(.52, .96),
    ];
    for (var i = 0; i < points.length; i++) {
      final point = Offset(size.width * points[i].dx, size.height * points[i].dy);
      final radius = size.width * (i.isEven ? .0045 : .003);
      canvas.drawCircle(
        point,
        radius * 3.5,
        Paint()
          ..color = accent.withOpacity(.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = accent.withOpacity(.52),
      );
      if (i % 3 == 0) {
        final sparkle = Path()
          ..moveTo(point.dx, point.dy - radius * 3)
          ..lineTo(point.dx + radius * .65, point.dy - radius * .65)
          ..lineTo(point.dx + radius * 3, point.dy)
          ..lineTo(point.dx + radius * .65, point.dy + radius * .65)
          ..lineTo(point.dx, point.dy + radius * 3)
          ..lineTo(point.dx - radius * .65, point.dy + radius * .65)
          ..lineTo(point.dx - radius * 3, point.dy)
          ..lineTo(point.dx - radius * .65, point.dy - radius * .65)
          ..close();
        canvas.drawPath(
          sparkle,
          Paint()..color = accent.withOpacity(.68),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SettingsSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// Settings - purani SettingsActivity ke saare features, naye dark neon style mein.
/// Data Kotlin ke SharedPreferences ("siya_prefs") mein save hota hai.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.bridge,
    this.embedded = false,
    this.onBackToHome,
  });

  final SiyaBridge bridge;
  final bool embedded;
  final VoidCallback? onBackToHome;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final _apiKey = TextEditingController();

  String _assistantName = 'Siya';
  String _assistantGender = 'female';
  String _personality = 'love';
  String _voice = 'Aoede';
  bool _memory = true;
  bool _wake = false;
  bool _callDetect = false; // default band
  bool _keepAwake = true;
  bool _aiBrowser = false;
  bool _callScreener = false;
  bool _locationPerm = false;
  bool _callScreenerRole = false;
  bool _allFiles = false;
  bool _loaded = false;
  bool _hideKeys = true;
  Color _primaryThemeColor = SiyaTheme.defaultAccent;

  bool _accessibility = false;
  bool _admin = false;
  bool _overlay = false;
  bool _batteryOk = false;
  bool _notif = true;
  int _missing = 0;
  int _memCount = 0;
  bool _bossEnrolled = false;
  int _bossSampleCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_apiKey]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _load() async {
    final s = await widget.bridge.getSettings();
    if (!mounted) return;
    setState(() {
      _apiKey.text = (s['api_key'] as String?) ?? '';
      _primaryThemeColor = SiyaTheme.parseAccent(s['app_accent_color'] ?? SiyaTheme.accent.value.value);
      SiyaTheme.accent.value = _primaryThemeColor;
      final rawMode = (s['selected_personality'] ?? s['personality_mode'] as String?) ?? 'love';
      _personality = (rawMode == 'gf') ? 'love' : rawMode;
      _assistantName = (s['assistant_name'] as String?) ?? 'Siya';
      _assistantGender = (s['assistant_gender'] as String?) ?? 'female';
      _voice = (s['live_voice'] as String?) ?? (_assistantName.toLowerCase() == 'kiyon' ? 'Fenrir' : 'Aoede');
      _memory = (s['memory_enabled'] as bool?) ?? true;
      _wake = (s['wake_word_enabled'] as bool?) ?? false;
      _callDetect = (s['call_detect_enabled'] as bool?) ?? false;
      _keepAwake = (s['keep_screen_on'] as bool?) ?? true;
      _aiBrowser = (s['ai_browser_enabled'] as bool?) ?? false;
      _callScreener = (s['call_screener'] as bool?) ?? false;
      _loaded = true;
    });
  }

  Future<void> _refreshStatus() async {
    final st = await widget.bridge.getStatus();
    if (!mounted) return;
    setState(() {
      _accessibility = (st['accessibility'] as bool?) ?? false;
      _admin = (st['admin'] as bool?) ?? false;
      _missing = (st['missing_permissions'] as int?) ?? 0;
      _overlay = (st['overlay'] as bool?) ?? false;
      _batteryOk = (st['battery_ok'] as bool?) ?? false;
      _notif = (st['notifications'] as bool?) ?? true;
      _memCount = (st['memory_count'] as int?) ?? 0;
      _allFiles = (st['all_files'] as bool?) ?? false;
      _locationPerm = (st['location_perm'] as bool?) ?? false;
      _callScreenerRole = (st['call_screener_role'] as bool?) ?? false;
    });
    try {
      final boss = await widget.bridge.getBossProfileStatus();
      if (!mounted) return;
      setState(() {
        _bossEnrolled = (boss['enrolled'] as bool?) ?? false;
        _bossSampleCount = ((boss['sampleCount'] as num?) ?? 0).toInt();
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    await widget.bridge.saveSettings({
      'api_key': _apiKey.text,
      'personality_mode': _personality,
      'selected_personality': _personality,
      'memory_enabled': _memory,
      'app_accent_color': _primaryThemeColor.value,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _saveApiKey() async {
    final key = _apiKey.text.trim();
    await widget.bridge.saveSettings({'api_key': key});
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Gemini API Key saved successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _saveThemeColor() async {
    await SiyaTheme.setAccent(_primaryThemeColor, widget.bridge.saveSettings);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Theme color updated and saved across app!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _grantPermissions() async {
    final left = await widget.bridge.requestPermissions();
    if (!mounted) return;
    setState(() => _missing = left);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Color.alphaBlend(_primaryThemeColor.withOpacity(.045), const Color(0xFFFFF5FA)),
      body: Stack(
        children: [
          Positioned.fill(
            child: _SettingsSilkBackground(primaryThemeColor: _primaryThemeColor),
          ),
          SafeArea(
            bottom: false,
            child: !_loaded
                ? const Center(child: CircularProgressIndicator(color: const Color(0xFFFF4D91)))
                : Column(
                    children: [
                      _header(context),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, bottomInset + 120),
                          children: [
                            _section('AI & Keys'),
                            _keyCard(),
                            const SizedBox(height: 10),

                            // AI Boss (Biometric Voiceprint Lock)
                            _section('AI Boss (Biometric Voiceprint Lock)'),
                            _card([
                              _action(
                                Icons.record_voice_over_rounded,
                                'AI Boss Voice Lock',
                                _bossEnrolled
                                    ? 'Verified Boss (Malik) - $_bossSampleCount samples active'
                                    : 'Voiceprint not enrolled - Tap to setup biometric voice lock',
                                _bossEnrolled,
                                () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AiBossScreen(bridge: widget.bridge),
                                    ),
                                  );
                                  _refreshStatus();
                                },
                              ),
                            ]),
                            const SizedBox(height: 10),

                            // 2. Feature Controls (Configurations & Toggles Only)
                            _section('Feature Controls'),
                            _card([
                              _switchRow(
                                'Obscura Web Agent',
                                _aiBrowser
                                    ? 'Chalu - headless background research active'
                                    : 'Band - background web research access',
                                _aiBrowser,
                                (v) {
                                  setState(() => _aiBrowser = v);
                                  widget.bridge.saveSettings({'ai_browser_enabled': v});
                                },
                              ),
                              _switchRow(
                                'Location Access',
                                _locationPerm
                                    ? 'Chalu - GPS aur maps access allowed'
                                    : 'Band - tap karke permission grant karein',
                                _locationPerm,
                                (v) async {
                                  if (v && !_locationPerm) {
                                    await widget.bridge.requestPermissions();
                                    await _refreshStatus();
                                  }
                                },
                              ),
                              _switchRow(
                                '"Hey Siya" Wake Word',
                                _wake
                                    ? 'Chalu - background mein "Hey Siya" sun rahi hai'
                                    : 'Band - "Hey Siya" bolkar jagane ke liye chalu karein',
                                _wake,
                                (v) {
                                  setState(() => _wake = v);
                                  widget.bridge.saveSettings({'wake_word_enabled': v});
                                },
                              ),
                              _switchRow(
                                'Screen WakeLock',
                                _keepAwake
                                    ? 'Chalu - AI chalne tak screen on rahegi'
                                    : 'Band - normal timeout par screen band hogi',
                                _keepAwake,
                                (v) {
                                  setState(() => _keepAwake = v);
                                  widget.bridge.saveSettings({'keep_screen_on': v});
                                },
                              ),
                              _switchRow(
                                'Unknown Call Screening',
                                _callScreener
                                    ? 'Chalu - anjaan number par AI call screen karegi'
                                    : 'Band - calls normal tarike se aayengi',
                                _callScreener,
                                (v) async {
                                  setState(() => _callScreener = v);
                                  await widget.bridge.saveSettings({'call_screener': v});
                                  if (v && !_callScreenerRole) {
                                    await widget.bridge.requestCallScreening();
                                  }
                                  await _refreshStatus();
                                },
                              ),
                              _action(
                                Icons.language_rounded,
                                'In-App Visible Browser',
                                'Screen par app ka apna dikhai dene wala browser kholo',
                                null,
                                () => widget.bridge.openBrowser(),
                              ),
                            ]),
                            const SizedBox(height: 10),

                            // Voice & Assistant Persona (Siya vs Kiyon)
                            _section('Voice & Assistant Persona'),
                            _voicePersonaSelector(),
                            const SizedBox(height: 10),

                            // 3. Personality
                            _section('Personality'),
                            _personalityGrid(),
                            const SizedBox(height: 10),

                            // 4. Theme Color
                            _section('Theme Color'),
                            _themeColorOption(),
                            const SizedBox(height: 10),

                            // 5. Access & Preferences
                            _section('Access & Preferences'),
                            _card([
                              // Clean App Permissions Card (Single Option Navigating to PermissionsScreen)
                              _action(
                                Icons.verified_user_rounded,
                                'App Permissions',
                                'Mic, Phone, Storage, Location aur sabhi permissions manage karein',
                                _missing == 0,
                                () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PermissionsScreen(bridge: widget.bridge),
                                    ),
                                  );
                                  _refreshStatus();
                                },
                              ),
                              // Security Settings
                              _action(
                                Icons.lock_outline_rounded,
                                'Security Settings',
                                'App lock, pattern, fingerprint',
                                null,
                                widget.bridge.openSecurity,
                              ),
                              // Profile
                              _action(
                                Icons.person_outline_rounded,
                                'Profile',
                                'Naam, prime contact',
                                null,
                                () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ProfileScreen(bridge: widget.bridge),
                                    ),
                                  );
                                },
                              ),
                              // Wallpaper
                              _action(
                                Icons.wallpaper_outlined,
                                'Wallpaper',
                                'Photo, video aur live wallpaper',
                                null,
                                () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => WallpaperScreen(bridge: widget.bridge),
                                    ),
                                  );
                                },
                              ),
                            ]),
                            const SizedBox(height: 16),

                            // 6. AI Data Tile
                            _aiDataTile(),
                            const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
          ),
          // Floating bottom navigation bar on top of the list view with proper safe elevation (only when not embedded)
          if (!widget.embedded)
            Positioned(
              left: 12,
              right: 12,
              bottom: math.max(12.0, bottomInset + 6.0),
              child: SiyaBottomNavigation(
                width: MediaQuery.sizeOf(context).width * .93,
                primaryColor: _primaryThemeColor,
                time: const AlwaysStoppedAnimation<double>(0),
                active: widget.bridge.isActive,
                homeActive: false,
                settingsActive: true,
                onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
                onChat: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Voice chat ke liye center mic tap karein.'),
                  behavior: SnackBarBehavior.floating,
                )),
                onMic: widget.bridge.toggleMic,
                onTools: () => Navigator.of(context).pushNamed('/power'),
                onSettings: () {},
              ),
            ),
        ],
      ),
    );
  }


  // ── pieces ───────────────────────────────────────────────────
  Widget _aiDataTile() => GestureDetector(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => MemoryScreen(bridge: widget.bridge)),
          );
          _refreshStatus();
        },
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: [
              const Color(0xFFFF4D91).withOpacity(0.22),
              const Color(0xFFFFB5D0).withOpacity(0.28),
            ]),
            border: Border.all(color: const Color(0xFFD6004C).withOpacity(0.4)),
            boxShadow: [BoxShadow(color: const Color(0xFFFF4D91).withOpacity(0.15), blurRadius: 18)],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _primaryThemeColor.withOpacity(.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _primaryThemeColor.withOpacity(0.6)),
                ),
                child: const Icon(Icons.psychology_alt_outlined, color: const Color(0xFFD6004C)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Data',
                        style: TextStyle(color: const Color(0xFF2A1C25), fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      _memCount == 0
                          ? 'Siya ki yaaddaasht aur chat history'
                          : '$_memCount messages yaad hain - chat history dekho',
                      style: TextStyle(color: const Color(0xFF6F6470), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8B7180)),
            ],
          ),
        ),
      );

  Widget _keyCard() => _card([
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Gemini API Key',
                  style: TextStyle(
                    color: Color(0xFF151019),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                GestureDetector(
                  onTap: _saveApiKey,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_primaryThemeColor, Color.lerp(_primaryThemeColor, const Color(0xFFFF0077), 0.5)!],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryThemeColor.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Save',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _field(_apiKey, 'Paste your API key', Icons.vpn_key_rounded, secret: true),
          ],
        ),
      ]);


  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                _iconBtn(Icons.arrow_back_ios_new_rounded, () {
                  if (widget.onBackToHome != null) {
                    widget.onBackToHome!();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                }),
                const SizedBox(width: 14),
                Expanded(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) => LinearGradient(
                      colors: [_primaryThemeColor, const Color(0xFF8D003A)],
                    ).createShader(rect),
                    child: const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.9,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        _primaryThemeColor.withOpacity(.02),
                        _primaryThemeColor,
                        _primaryThemeColor.withOpacity(.08),
                      ]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: _primaryThemeColor,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        _primaryThemeColor.withOpacity(.08),
                        _primaryThemeColor,
                        _primaryThemeColor.withOpacity(.02),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _primaryThemeColor.withOpacity(.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _primaryThemeColor.withOpacity(0.6)),
          ),
          child: Icon(icon, color: const Color(0xFF2A1C25), size: 20),
        ),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 15, 0, 8),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: _primaryThemeColor, size: 17),
            const SizedBox(width: 8),
            Text(
              t.toUpperCase(),
              style: TextStyle(
                color: _primaryThemeColor,
                fontSize: 12,
                letterSpacing: 1.65,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1.4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    _primaryThemeColor.withOpacity(.8),
                    _primaryThemeColor.withOpacity(.02),
                  ]),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.68),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withOpacity(.96), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: _primaryThemeColor.withOpacity(.09),
              blurRadius: 22,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: _primaryThemeColor.withOpacity(.09),
              blurRadius: 12,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              children[i],
            ],
          ],
        ),
      );

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool secret = false, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      obscureText: secret && _hideKeys,
      keyboardType: keyboard,
      style: const TextStyle(color: Color(0xFF2A1C25)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: const Color(0xFF756A76)),
        prefixIcon: Icon(icon, color: _primaryThemeColor, size: 20),
        suffixIcon: secret
            ? IconButton(
                icon: Icon(_hideKeys ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: const Color(0xFF8B7180), size: 20),
                onPressed: () => setState(() => _hideKeys = !_hideKeys),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFFFF9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primaryThemeColor.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primaryThemeColor.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primaryThemeColor, width: 1.4),
        ),
      ),
    );
  }

  Widget _voicePersonaSelector() {
    final isKiyon = _assistantName.toLowerCase() == 'kiyon';
    return _card([
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _VoicePersonaChip(
                    name: 'Siya',
                    title: 'Female Voice 🌸',
                    subtitle: 'Sweet, emotional & caring companion (Aoede)',
                    selected: !isKiyon,
                    color: const Color(0xFFFF2A6D),
                    icon: Icons.female_rounded,
                    onTap: () async {
                      setState(() {
                        _assistantName = 'Siya';
                        _assistantGender = 'female';
                        _voice = 'Aoede';
                      });
                      await widget.bridge.saveSettings({
                        'assistant_name': 'Siya',
                        'assistant_gender': 'female',
                        'live_voice': 'Aoede',
                      });
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('🌸 Siya (Female Voice) active! Home page name updated.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VoicePersonaChip(
                    name: 'Kiyon',
                    title: 'Male Voice ⚡',
                    subtitle: 'Khatarnak, bhaari male voice • Sir & Boss mode (Fenrir)',
                    selected: isKiyon,
                    color: const Color(0xFF02A3FC),
                    icon: Icons.male_rounded,
                    onTap: () async {
                      setState(() {
                        _assistantName = 'Kiyon';
                        _assistantGender = 'male';
                        _voice = 'Fenrir';
                      });
                      await widget.bridge.saveSettings({
                        'assistant_name': 'Kiyon',
                        'assistant_gender': 'male',
                        'live_voice': 'Fenrir',
                      });
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('⚡ Kiyon (Khatarnak Male Voice - Sir/Boss Mode) active! Home page name updated.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (isKiyon ? const Color(0xFF02A3FC) : const Color(0xFFFF2A6D)).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isKiyon ? const Color(0xFF02A3FC) : const Color(0xFFFF2A6D)).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isKiyon ? Icons.shield_rounded : Icons.favorite_rounded,
                    color: isKiyon ? const Color(0xFF02A3FC) : const Color(0xFFFF2A6D),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isKiyon
                          ? 'Kiyon Active: Deep khatarnak voice se aapko "Sir" aur "Boss" bulayega. Home screen par KIYON AI dikhega.'
                          : 'Siya Active: Sweet female voice se baat karegi. Home screen par SIYA AI dikhega.',
                      style: TextStyle(
                        color: isKiyon ? const Color(0xFF0284C7) : const Color(0xFFD6004C),
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _personalityGrid() {
    const choices = <(String, String, IconData)>[
      ('friendly', 'Friendly 😊', Icons.sentiment_very_satisfied_rounded),
      ('professional', 'Professional 💼', Icons.work_outline_rounded),
      ('assistant', 'Assistant 🤖', Icons.smart_toy_outlined),
      ('love', 'Love ❤️', Icons.favorite_rounded),
    ];
    return _card([
      LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: choices.map((choice) {
              final norm = _personality.toLowerCase();
              final isChoiceLove = (norm == 'gf' || norm == 'love') && choice.$1 == 'love';
              final selected = norm == choice.$1 || isChoiceLove;
              return SizedBox(
                width: itemWidth,
                child: _PersonalityChip(
                  title: choice.$2,
                  icon: choice.$3,
                  selected: selected,
                  color: _primaryThemeColor,
                  onTap: () async {
                    setState(() => _personality = choice.$1);
                    await widget.bridge.saveSettings({
                      'personality_mode': choice.$1,
                      'selected_personality': choice.$1,
                    });
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    ]);
  }

  Widget _themeColorOption() {
    return _action(
      Icons.palette_rounded,
      'Theme Accent Color',
      'Pura app ka theme color badlein (vibrant palette)',
      null,
      () => _showThemeColorDialog(),
    );
  }

  void _showThemeColorDialog() {
    Color tempColor = _primaryThemeColor;
    const colors = <(String, Color)>[
      ('Neon Rose', Color(0xFFFF2A6D)),
      ('Crimson Red', Color(0xFFE50040)),
      ('Sunset Orange', Color(0xFFFF6B35)),
      ('Amber Gold', Color(0xFFFFB800)),
      ('Emerald Mint', Color(0xFF00C896)),
      ('Neon Lime', Color(0xFF10B981)),
      ('Electric Cyan', Color(0xFF02A3FC)),
      ('Deep Ocean', Color(0xFF0284C7)),
      ('Royal Purple', Color(0xFF8B5CF6)),
      ('Electric Violet', Color(0xFF7928CA)),
      ('Fuchsia Pink', Color(0xFFE91E63)),
      ('Coral Blush', Color(0xFFFF5376)),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B192A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: tempColor.withOpacity(0.5), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tempColor,
                  boxShadow: [
                    BoxShadow(color: tempColor.withOpacity(0.4), blurRadius: 10),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Theme Accent Color',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: colors.map((item) {
                final name = item.$1;
                final col = item.$2;
                final selected = col.value == tempColor.value;
                return GestureDetector(
                  onTap: () {
                    setDialogState(() => tempColor = col);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: col,
                          border: Border.all(
                            color: Colors.white,
                            width: selected ? 3.5 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: col.withOpacity(selected ? 0.6 : 0.2),
                              blurRadius: selected ? 14 : 6,
                              spreadRadius: selected ? 2 : 0,
                            ),
                          ],
                        ),
                        child: selected
                            ? const Center(
                                child: Icon(Icons.check_rounded, color: Colors.white, size: 24),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white60,
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _primaryThemeColor = tempColor);
                SiyaTheme.setAccent(tempColor, widget.bridge.saveSettings);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Theme color updated!'),
                    backgroundColor: tempColor,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tempColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Apply & Save', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(String title, String sub, bool v, ValueChanged<bool> on) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Color(0xFF2A1C25), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: const Color(0xFF756A76), fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: v,
            onChanged: on,
            activeColor: const Color(0xFFD6004C),
            activeTrackColor: const Color(0xFFFFB5D0).withOpacity(0.6),
          ),
        ],
      );

  /// ok: true = green, false = red, null = neutral.
  Widget _action(IconData icon, String title, String sub, bool? ok, VoidCallback onTap) {
    final statusColor = ok == null ? const Color(0xFF8B7180) : (ok ? SiyaColors.ok : SiyaColors.bad);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.54),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _primaryThemeColor.withOpacity(.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _primaryThemeColor.withOpacity(.12),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 1.3),
                boxShadow: [
                  BoxShadow(
                    color: _primaryThemeColor.withOpacity(.10),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: _primaryThemeColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF2A1C25),
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ok == null ? const Color(0xFF756A76) : statusColor,
                      fontSize: 12.5,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.55),
                shape: BoxShape.circle,
                border: Border.all(color: _primaryThemeColor.withOpacity(.13)),
              ),
              child: Icon(Icons.chevron_right_rounded, color: _primaryThemeColor, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalityChip extends StatefulWidget {
  const _PersonalityChip({
    required this.title,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_PersonalityChip> createState() => _PersonalityChipState();
}

class _PersonalityChipState extends State<_PersonalityChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? .96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: widget.selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.color,
                        Color.lerp(widget.color, const Color(0xFFE600A9), .74)!,
                      ],
                    )
                  : null,
              color: widget.selected ? null : Colors.white.withOpacity(.66),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: widget.selected ? Colors.white : widget.color.withOpacity(.23),
                width: widget.selected ? 1.6 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(widget.selected ? .30 : .08),
                  blurRadius: widget.selected ? 17 : 9,
                  offset: const Offset(0, 4),
                ),
                if (widget.selected)
                  const BoxShadow(
                    color: Color(0x55FFFFFF),
                    blurRadius: 6,
                    offset: Offset(0, -2),
                  ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: widget.selected ? Colors.white : widget.color,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected ? Colors.white : const Color(0xFF2A1C25),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.0,
                    ),
                  ),
                ),
                if (widget.selected) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _VoicePersonaChip extends StatefulWidget {
  const _VoicePersonaChip({
    required this.name,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String name;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_VoicePersonaChip> createState() => _VoicePersonaChipState();
}

class _VoicePersonaChipState extends State<_VoicePersonaChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color,
                      Color.lerp(widget.color, Colors.black, 0.28)!,
                    ],
                  )
                : null,
            color: widget.selected ? null : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.selected ? Colors.white : widget.color.withOpacity(0.3),
              width: widget.selected ? 2.0 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(widget.selected ? 0.35 : 0.08),
                blurRadius: widget.selected ? 14 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected ? Colors.white.withOpacity(0.25) : widget.color.withOpacity(0.12),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: widget.selected ? Colors.white : widget.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.selected ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                style: TextStyle(
                  color: widget.selected ? Colors.white.withOpacity(0.9) : const Color(0xFF64748B),
                  fontSize: 11.0,
                  height: 1.25,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
