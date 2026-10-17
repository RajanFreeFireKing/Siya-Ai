import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/aurora_background.dart';
import 'features_screen.dart';
import 'location_screen.dart';
import 'memory_screen.dart';
import 'power_features_screen.dart';
import 'profile_screen.dart';
import 'wallpaper_screen.dart';

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
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _grantPermissions() async {
    final left = await widget.bridge.requestPermissions();
    if (!mounted) return;
    setState(() => _missing = left);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SiyaColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground()),
          SafeArea(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator(color: SiyaColors.cyan))
              : Column(
                  children: [
                    _header(context),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          _section('AI & Keys'),
                          _card([
                            _field(_apiKey, 'Gemini API Key', Icons.vpn_key_outlined, secret: true),
                          ]),
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
                          _card([
                            _chips(
                              value: _personality,
                              options: const {
                                'gf': 'Friendly',
                                'professional': 'Professional',
                                'assistant': 'Assistant',
                                'love': 'Love \u2764',
                              },
                              onChanged: (v) => setState(() => _personality = v),
                            ),
                          ]),
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
                            leading: const Icon(Icons.bolt_rounded, color: SiyaColors.cyanSoft),
                            title: const Text('Power Features', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: const Text('WhatsApp reply, call screener, SOS, Ghost Mode, Gaming HUD', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PowerFeaturesScreen(bridge: widget.bridge))),
                          ),
                          const SizedBox(height: 12),
                          _saveButton(),
                        ],
                      ),
                    ),
                  ],
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
              SiyaColors.cyan.withOpacity(0.22),
              SiyaColors.purple.withOpacity(0.28),
            ]),
            border: Border.all(color: SiyaColors.cyanSoft.withOpacity(0.4)),
            boxShadow: [BoxShadow(color: SiyaColors.cyan.withOpacity(0.15), blurRadius: 18)],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF071826),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SiyaColors.cyan.withOpacity(0.6)),
                ),
                child: const Icon(Icons.psychology_alt_outlined, color: SiyaColors.cyanSoft),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Data',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      _memCount == 0
                          ? 'Siya ki yaaddaasht aur chat history'
                          : '$_memCount messages yaad hain - chat history dekho',
                      style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      );

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
        child: Row(
          children: [
            _iconBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.of(context).pop()),
            const SizedBox(width: 14),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => const LinearGradient(
                colors: [SiyaColors.cyanSoft, SiyaColors.violet],
              ).createShader(r),
              child: const Text('Settings',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
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
            color: const Color(0xFF071826),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: SiyaColors.cyan.withOpacity(0.6)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 0, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(
              color: SiyaColors.cyanSoft.withOpacity(0.85),
              fontSize: 12,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            )),
      );

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SiyaColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SiyaColors.cyan.withOpacity(0.18)),
          boxShadow: [BoxShadow(color: SiyaColors.purple.withOpacity(0.06), blurRadius: 18)],
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
        prefixIcon: Icon(icon, color: SiyaColors.cyanSoft.withOpacity(0.8), size: 20),
        suffixIcon: secret
            ? IconButton(
                icon: Icon(_hideKeys ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.white54, size: 20),
                onPressed: () => setState(() => _hideKeys = !_hideKeys),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF071420),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: SiyaColors.cyan.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: SiyaColors.cyan.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SiyaColors.cyan, width: 1.4),
        ),
      ),
    );
  }

  Widget _chips({
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final sel = e.key == value;
        return GestureDetector(
          onTap: () => onChanged(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: sel
                  ? const LinearGradient(colors: [SiyaColors.cyan, SiyaColors.purple])
                  : null,
              color: sel ? null : const Color(0xFF071420),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SiyaColors.cyan.withOpacity(sel ? 0 : 0.25)),
            ),
            child: Text(e.value,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                )),
          ),
        );
      }).toList(),
    );
  }

  Widget _switchRow(String title, String sub, bool v, ValueChanged<bool> on) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: v,
            onChanged: on,
            activeColor: SiyaColors.cyanSoft,
            activeTrackColor: SiyaColors.purple.withOpacity(0.6),
          ),
        ],
      );

  /// ok: true = green, false = red, null = neutral.
  Widget _action(IconData icon, String title, String sub, bool? ok, VoidCallback onTap) {
    final color = ok == null ? Colors.white54 : (ok ? SiyaColors.ok : SiyaColors.bad);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF071420),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SiyaColors.cyan.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, color: SiyaColors.cyanSoft, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: color, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
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
            gradient: const LinearGradient(colors: [SiyaColors.cyan, SiyaColors.purple]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: SiyaColors.cyan.withOpacity(0.35), blurRadius: 16)],
          ),
          child: const Text('Save',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      );
}
