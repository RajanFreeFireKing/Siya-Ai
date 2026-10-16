import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

/// Naye features ke ON/OFF switch: WhatsApp auto-reply, Call screener, UPI ledger, SOS, Ghost Mode, Gaming HUD.
class PowerFeaturesScreen extends StatefulWidget {
  const PowerFeaturesScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<PowerFeaturesScreen> createState() => _PowerFeaturesScreenState();
}

class _PowerFeaturesScreenState extends State<PowerFeaturesScreen> {
  static const MethodChannel _m = MethodChannel('siya/engine');
  Map<String, dynamic> _s = {};
  final _names = TextEditingController();
  final _sos = TextEditingController();
  final _code = TextEditingController();
  final _spam = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.bridge.getSettings();
    if (!mounted) return;
    setState(() {
      _s = s;
      _names.text = (s['wa_reply_names'] as String?) ?? '';
      _sos.text = (s['sos_contacts'] as String?) ?? '';
      _code.text = (s['ghost_code'] as String?) ?? '2580';
      _spam.text = (s['spam_numbers'] as String?) ?? '';
    });
  }

  Future<void> _set(String k, dynamic v) async {
    setState(() => _s[k] = v);
    await widget.bridge.saveSettings({k: v});
  }

  bool _b(String k) => (_s[k] as bool?) ?? false;

  Widget _sw(String k, String title, String sub) => SwitchListTile(
        value: _b(k),
        onChanged: (v) => _set(k, v),
        activeColor: SiyaColors.cyanSoft,
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      );

  Widget _field(TextEditingController c, String label, String key, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: TextField(
          controller: c,
          keyboardType: type,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white54), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))),
          onSubmitted: (v) => _set(key, v.trim()),
          onEditingComplete: () => _set(key, c.text.trim()),
        ),
      );

  Widget _btn(String t, VoidCallback f) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: OutlinedButton(onPressed: f, child: Text(t)),
      );

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(t, style: const TextStyle(color: SiyaColors.cyanSoft, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SiyaColors.bg,
      appBar: AppBar(backgroundColor: SiyaColors.bg, title: const Text('Power Features')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _h('WhatsApp auto-reply'),
          _sw('wa_autoreply', 'Auto-reply ON', 'Naye personal message ka Gemini se jawab (group nahi). Message text Google Gemini ko jaata hai. Reply ke saath "(Siya auto-reply)" likha aata hai.'),
          _field(_names, 'Sirf in naamon ko reply (comma se, khaali = sabko)', 'wa_reply_names'),
          _btn('Notification access ON karo', widget.bridge.openNotificationAccess),
          _h('Call screener'),
          _sw('call_screener', 'Anjaan number par AI se call uthwao', 'Speakerphone par Siya poochhti hai "kis kaam se call?", jawab text mein dikhta hai. Kuch phones par mic call mein block hota hai.'),
          _field(_spam, 'Spam numbers / shuruaati ank (comma se) - turant reject', 'spam_numbers'),
          _btn('Call-screening role do', () => _m.invokeMethod<void>('requestCallScreening')),
          _h('UPI kharcha'),
          _sw('ledger_enabled', 'SMS se kharcha track', 'Bank / UPI SMS ka amount phone ke andar ledger mein. "aaj ka kharcha batao" bolo.'),
          _h('Emergency SOS'),
          _field(_sos, 'Emergency numbers (comma se)', 'sos_contacts', type: TextInputType.phone),
          _sw('sos_volume_enabled', 'Volume-down 3 baar = SOS', 'Location SMS + audio recording. Accessibility ON honi chahiye.'),
          _h('Ghost Mode'),
          _field(_code, 'Secret code (sirf ank)', 'ghost_code', type: TextInputType.number),
          _sw('ghost_mode', 'App ko Calculator banao', 'Code + "=" dabane par hi Siya khulti hai. Code bhoolna mat!'),
          _h('Gaming'),
          _sw('game_hud', 'Gaming HUD dikhao', 'Game ke kone mein timer, mic aur macro buttons. Macro banane ke liye bolo: "gloo wall macro sikho".'),
          _btn('Game time ke liye Usage access', () => _m.invokeMethod<void>('openUsageAccess')),
          _btn('Display over other apps', widget.bridge.openOverlaySettings),
        ],
      ),
    );
  }
}
