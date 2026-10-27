import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_bottom_navigation.dart';

import 'features_screen.dart';
import 'location_screen.dart';
import 'memory_screen.dart';
import 'power_features_screen.dart';
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
  const SettingsScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final _apiKey = TextEditingController();

  String _personality = 'gf';
  String _voice = 'Aoede';
  bool _memory = true;
  bool _wake = false;
  bool _callDetect = false; // default band
  bool _keepAwake = true;
  bool _aiBrowser = false;
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
      _personality = (s['personality_mode'] as String?) ?? 'gf';
      _voice = (s['live_voice'] as String?) ?? 'Aoede';
      _memory = (s['memory_enabled'] as bool?) ?? true;
      _wake = (s['wake_word_enabled'] as bool?) ?? false;
      _callDetect = (s['call_detect_enabled'] as bool?) ?? false;
      _keepAwake = (s['keep_screen_on'] as bool?) ?? true;
      _aiBrowser = (s['ai_browser_enabled'] as bool?) ?? false;
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
    });
  }

  Future<void> _save() async {
    await widget.bridge.saveSettings({
      'api_key': _apiKey.text,
      'personality_mode': _personality,
      'memory_enabled': _memory,
      'app_accent_color': _primaryThemeColor.value,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _grantPermissions() async {
    final left = await widget.bridge.requestPermissions();
    if (!mounted) return;
    setState(() => _missing = left);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.alphaBlend(_primaryThemeColor.withOpacity(.045), const Color(0xFFFFF5FA)),
      bottomNavigationBar: SiyaBottomNavigation(
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
        onTools: () => Navigator.of(context).pushNamed('/features'),
        onSettings: () {},
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _SettingsSilkBackground(primaryThemeColor: _primaryThemeColor),
          ),
          SafeArea(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator(color: const Color(0xFFFF4D91)))
              : Column(
                  children: [
                    _header(context),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          _section('AI & Keys'),
                          _keyCard(),
                          _card([
                            _action(Icons.tune, 'Features', 'Hey Siya, Browser, Screen on, Call detect, Awaaz focus', null, () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => FeaturesScreen(bridge: widget.bridge)));
                              _load();
                            }),
                            _action(Icons.person_outline, 'Profile', 'Naam, prime contact', null, () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => ProfileScreen(bridge: widget.bridge)));
                            }),
                            _action(Icons.wallpaper_outlined, 'Wallpaper', 'Photo, video aur live wallpaper', null, () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => WallpaperScreen(bridge: widget.bridge)));
                            }),
                            _action(Icons.public, 'AI Browser',
                                _aiBrowser ? 'ON - tap karke browser kholo' : 'Band - Features mein ON karo', _aiBrowser, () async {
                              if (!_aiBrowser) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Pehle Features mein AI Browser ON karo')));
                                return;
                              }
                              await widget.bridge.openBrowser();
                            }),
                            _action(Icons.location_on_outlined, 'Location', 'Map, search, location set karo', null, () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => LocationScreen(bridge: widget.bridge)));
                            }),
                          ]),
                          _section('Personality'),
                          _personalityGrid(),
                          const SizedBox(height: 10),
                          _section('Theme Color'),
                          _themeColorPicker(),
                          _section('Access & Security'),
                          _card([
                            _action(
                              Icons.accessibility_new,
                              'Accessibility',
                              _accessibility ? 'Full control on' : 'Off - tap to enable',
                              _accessibility,
                              () async {
                                await widget.bridge.openAccessibility();
                              },
                            ),
                            _action(
                              Icons.admin_panel_settings_outlined,
                              'Device admin',
                              _admin ? 'Active' : 'Inactive - tap to enable',
                              _admin,
                              () async {
                                await widget.bridge.toggleAdmin();
                                _refreshStatus();
                              },
                            ),
                            _action(
                              Icons.verified_user_outlined,
                              'Permissions',
                              _missing == 0 ? 'All granted' : '$_missing pending - tap to grant',
                              _missing == 0,
                              _grantPermissions,
                            ),
                            _action(
                              Icons.notifications_active_outlined,
                              'Notifications',
                              _notif ? 'On - background mein chalne ke liye' : 'Off - tap karke Permissions do',
                              _notif,
                              _grantPermissions,
                            ),
                            _action(
                              Icons.layers_outlined,
                              'Display over other apps',
                              _overlay ? 'On - dusre app ke upar Siya dikhegi' : 'Off - app kholne / orb ke liye ON karo',
                              _overlay,
                              () async {
                                await widget.bridge.openOverlaySettings();
                              },
                            ),
                            _action(
                              Icons.battery_charging_full_outlined,
                              'Background chalne do',
                              _batteryOk ? 'Battery optimization off' : 'Tap karo - Siya ko band hone se roko',
                              _batteryOk,
                              () async {
                                await widget.bridge.requestBatteryExemption();
                              },
                            ),
                            _action(
                              Icons.folder_open_outlined,
                              'All files access',
                              _allFiles ? 'ON - Siya files dekh, badal aur share kar sakti hai' : 'Off - tap karke ON karo',
                              _allFiles,
                              () async {
                                await widget.bridge.openAllFilesSettings();
                              },
                            ),
                            _action(
                              Icons.assistant_outlined,
                              'Default assistant',
                              'Power button se Siya start karo',
                              null,
                              widget.bridge.setDefaultAssistant,
                            ),
                            _action(
                              Icons.lock_outline,
                              'Security settings',
                              'App lock, pattern, fingerprint',
                              null,
                              widget.bridge.openSecurity,
                            ),
                          ]),
                          const SizedBox(height: 18),
                          _aiDataTile(),
                          const SizedBox(height: 8),
                          ListTile(
                            leading: const Icon(Icons.bolt_rounded, color: const Color(0xFFD6004C)),
                            title: const Text('Power Features', style: TextStyle(color: const Color(0xFF2A1C25), fontWeight: FontWeight.w600)),
                            subtitle: const Text('WhatsApp reply, call screener, SOS, Ghost Mode, Gaming HUD', style: TextStyle(color: const Color(0xFF6F6470), fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B7180)),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PowerFeaturesScreen(bridge: widget.bridge))),
                          ),
                          const SizedBox(height: 12),
                          _saveButton(),
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
            const Text(
              'Gemini API Key',
              style: TextStyle(
                color: Color(0xFF151019),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
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
                  if (Navigator.of(context).canPop()) {
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

  Widget _personalityGrid() {
    const choices = <(String, String, IconData)>[
      ('gf', 'Friendly', Icons.check_circle_rounded),
      ('professional', 'Professional', Icons.work_outline_rounded),
      ('assistant', 'Assistant', Icons.smart_toy_outlined),
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
              final selected = _personality == choice.$1;
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

  Widget _themeColorPicker() {
    const colors = <Color>[
      Color(0xFFFF2A6D),
      Color(0xFFE91E63),
      Color(0xFFFF6B35),
      Color(0xFF8B5CF6),
      Color(0xFF02A3FC),
      Color(0xFF00A884),
      Color(0xFF111827),
      Color(0xFFCE2DDF),
    ];
    return _card([
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: colors.map((color) {
          final selected = color.value == _primaryThemeColor.value;
          return Semantics(
            button: true,
            label: 'Choose theme color',
            child: GestureDetector(
              onTap: () async {
                setState(() => _primaryThemeColor = color);
                await SiyaTheme.setAccent(color, widget.bridge.saveSettings);
              },
              child: AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: Colors.white,
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(selected ? .38 : .15),
                        blurRadius: selected ? 13 : 7,
                      ),
                    ],
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                      : null,
                ),
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 8),
      const Text(
        'Theme accent updates this screen immediately.',
        style: TextStyle(color: Color(0xFF756A76), fontSize: 12),
      ),
    ]);
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

  Widget _saveButton() => GestureDetector(
        onTap: _save,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_primaryThemeColor, Color.lerp(_primaryThemeColor, const Color(0xFFFF00A8), .75)!]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: _primaryThemeColor.withOpacity(0.35), blurRadius: 16)],
          ),
          child: const Text('Save',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      );
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
                  size: 21,
                  color: widget.selected ? Colors.white : widget.color,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected ? Colors.white : const Color(0xFF2A1C25),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
