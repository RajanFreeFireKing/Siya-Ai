import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

class _PermissionsSilkBackground extends StatelessWidget {
  const _PermissionsSilkBackground({required this.primaryThemeColor});
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
            painter: _PermissionsSilkPainter(primaryThemeColor),
            size: Size.infinite,
          ),
        ),
      );
}

class _PermissionsSilkPainter extends CustomPainter {
  const _PermissionsSilkPainter(this.accent);
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
    }
  }

  @override
  bool shouldRepaint(covariant _PermissionsSilkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.bridge});
  final SiyaBridge bridge;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  Color _primaryThemeColor = SiyaTheme.defaultAccent;
  bool _loaded = false;

  int _missing = 0;
  bool _accessibility = false;
  bool _admin = false;
  bool _overlay = false;
  bool _batteryOk = false;
  bool _notif = true;
  bool _allFiles = false;
  bool _locationPerm = false;
  bool _micPerm = false;
  bool _phonePerm = false;
  bool _callLogPerm = false;
  bool _smsPerm = false;
  bool _callScreenerRole = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _primaryThemeColor = SiyaTheme.accent.value;
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final st = await widget.bridge.getStatus();
    if (!mounted) return;
    setState(() {
      _primaryThemeColor = SiyaTheme.accent.value;
      _accessibility = (st['accessibility'] as bool?) ?? false;
      _admin = (st['admin'] as bool?) ?? false;
      _missing = (st['missing_permissions'] as int?) ?? 0;
      _overlay = (st['overlay'] as bool?) ?? false;
      _batteryOk = (st['battery_ok'] as bool?) ?? false;
      _notif = (st['notifications'] as bool?) ?? true;
      _allFiles = (st['all_files'] as bool?) ?? false;
      _locationPerm = (st['location_perm'] as bool?) ?? false;
      _micPerm = (st['mic_perm'] as bool?) ?? false;
      _phonePerm = (st['phone_perm'] as bool?) ?? false;
      _callLogPerm = (st['call_log_perm'] as bool?) ?? false;
      _smsPerm = (st['sms_perm'] as bool?) ?? false;
      _callScreenerRole = (st['call_screener_role'] as bool?) ?? false;
      _loaded = true;
    });
  }

  Future<void> _grantAll() async {
    final left = await widget.bridge.requestPermissions();
    if (!mounted) return;
    setState(() => _missing = left);
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Color.alphaBlend(_primaryThemeColor.withOpacity(.045), const Color(0xFFFFF5FA)),
      body: Stack(
        children: [
          Positioned.fill(
            child: _PermissionsSilkBackground(primaryThemeColor: _primaryThemeColor),
          ),
          SafeArea(
            bottom: false,
            child: !_loaded
                ? Center(child: CircularProgressIndicator(color: _primaryThemeColor))
                : Column(
                    children: [
                      _header(context),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, bottomInset + 32),
                          children: [
                            _healthBanner(),
                            const SizedBox(height: 12),
                            _section('Core Permissions'),
                            _card([
                              // a) Microphone
                              _action(
                                Icons.mic_rounded,
                                'Microphone',
                                _micPerm
                                    ? 'Allowed - Voice commands & Hey Siya ready'
                                    : 'Pending - Tap karke mic permission dein',
                                _micPerm,
                                _grantAll,
                              ),
                              // b) Phone & Call Screening
                              _action(
                                Icons.phone_in_talk_rounded,
                                'Phone & Call Screening',
                                (_phonePerm && _callLogPerm)
                                    ? 'Allowed - In-call audio & caller detection active'
                                    : 'Pending - Caller naam & unknown call ke liye zaroori',
                                _phonePerm && _callLogPerm,
                                () async {
                                  await _grantAll();
                                  if (!_callScreenerRole) {
                                    await widget.bridge.requestCallScreening();
                                  }
                                },
                              ),
                              // c) Storage / Files Access
                              _action(
                                Icons.folder_open_rounded,
                                'Storage & Files Access',
                                _allFiles
                                    ? 'Allowed (Full) - Local models, media & documents'
                                    : 'Off - Tap karke All files permission ON karein',
                                _allFiles,
                                () async {
                                  await widget.bridge.openAllFilesSettings();
                                  _refreshStatus();
                                },
                              ),
                              // d) Location
                              _action(
                                Icons.location_on_rounded,
                                'Location (GPS & Maps)',
                                _locationPerm
                                    ? 'Allowed - Weather, maps & nearby queries'
                                    : 'Pending - Mausam aur location queries ke liye do',
                                _locationPerm,
                                _grantAll,
                              ),
                              // e) SMS / Kharcha
                              _action(
                                Icons.sms_rounded,
                                'SMS & Kharcha Ledger',
                                _smsPerm
                                    ? 'Allowed - Bank/UPI SMS expense tracking'
                                    : 'Pending - Expense tracker & ledger ke liye do',
                                _smsPerm,
                                _grantAll,
                              ),
                            ]),
                            const SizedBox(height: 12),
                            _section('System & Background Access'),
                            _card([
                              // f) Notifications
                              _action(
                                Icons.notifications_active_rounded,
                                'Notifications',
                                _notif
                                    ? 'Allowed - Background alerts & call pills'
                                    : 'Off - Tap karke notification alert ON karein',
                                _notif,
                                () async {
                                  await widget.bridge.openNotificationAccess();
                                  _refreshStatus();
                                },
                              ),
                              // g) System Overlay (Display over other apps)
                              _action(
                                Icons.layers_rounded,
                                'Display Over Other Apps',
                                _overlay
                                    ? 'Allowed - Floating orb & assistant window active'
                                    : 'Off - Dusre apps ke upar orb dikhane ke liye ON karein',
                                _overlay,
                                () async {
                                  await widget.bridge.openOverlaySettings();
                                  _refreshStatus();
                                },
                              ),
                              // h) Battery Optimization
                              _action(
                                Icons.battery_charging_full_rounded,
                                'Background Battery Exemption',
                                _batteryOk
                                    ? 'Allowed - Background wake-word active rahega'
                                    : 'Off - Siya ko sleep hone se roko',
                                _batteryOk,
                                () async {
                                  await widget.bridge.requestBatteryExemption();
                                  _refreshStatus();
                                },
                              ),
                              // i) Accessibility Service
                              _action(
                                Icons.accessibility_new_rounded,
                                'Accessibility Service',
                                _accessibility
                                    ? 'Allowed - Full assistant navigation on'
                                    : 'Off - System actions & volume SOS ke liye ON karein',
                                _accessibility,
                                () async {
                                  await widget.bridge.openAccessibility();
                                  _refreshStatus();
                                },
                              ),
                              // j) Default Assistant
                              _action(
                                Icons.assistant_rounded,
                                'Default Assistant Role',
                                'Power button ya home gesture se Siya shuru karein',
                                null,
                                widget.bridge.setDefaultAssistant,
                              ),
                            ]),
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

  Widget _healthBanner() {
    final isAllGood = _missing == 0 && _overlay && _batteryOk && _notif;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.75),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isAllGood ? SiyaColors.ok.withOpacity(0.5) : _primaryThemeColor.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isAllGood ? SiyaColors.ok : _primaryThemeColor).withOpacity(0.12),
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
              shape: BoxShape.circle,
              color: (isAllGood ? SiyaColors.ok : _primaryThemeColor).withOpacity(0.14),
            ),
            child: Icon(
              isAllGood ? Icons.verified_rounded : Icons.security_update_warning_rounded,
              color: isAllGood ? SiyaColors.ok : _primaryThemeColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAllGood ? 'Sabhi Permissions Active Hain' : 'Permissions Setup Needed',
                  style: const TextStyle(
                    color: Color(0xFF2A1C25),
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isAllGood
                      ? 'Siya AI bina kisi rukawat ke poore phone par chal rahi hai.'
                      : '$_missing zaroori permissions baaki hain. Ek tap mein grant karein.',
                  style: const TextStyle(color: Color(0xFF6F6470), fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isAllGood)
            GestureDetector(
              onTap: _grantAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_primaryThemeColor, Color.lerp(_primaryThemeColor, const Color(0xFFFF0077), 0.5)!],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryThemeColor.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Grant All',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
                      'App Permissions',
                      style: TextStyle(
                        fontSize: 27,
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
              child: Icon(
                ok == true ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: ok == true ? SiyaColors.ok : _primaryThemeColor,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
