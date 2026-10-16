import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_ui.dart';

/// Features: saare on/off switch ek alag screen mein. Har badlaav turant save hota hai.
class FeaturesScreen extends StatefulWidget {
  const FeaturesScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<FeaturesScreen> createState() => _FeaturesScreenState();
}

class _FeaturesScreenState extends State<FeaturesScreen> with WidgetsBindingObserver {
  final _ppnKey = TextEditingController();
  bool _wake = false;
  bool _aiBrowser = false;
  bool _keepAwake = true;
  bool _callDetect = false;
  String _focus = 'normal';
  bool _mediaAccess = false;
  bool _ppnModel = false;
  bool _loaded = false;
  bool _hideKey = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ppnKey.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _status();
  }

  Future<void> _load() async {
    final s = await widget.bridge.getSettings();
    if (!mounted) return;
    setState(() {
      _wake = (s['wake_word_enabled'] as bool?) ?? false;
      _aiBrowser = (s['ai_browser_enabled'] as bool?) ?? false;
      _keepAwake = (s['keep_screen_on'] as bool?) ?? true;
      _callDetect = (s['call_detect_enabled'] as bool?) ?? false;
      _focus = (s['voice_focus'] as String?) ?? 'normal';
      _ppnKey.text = (s['picovoice_key'] as String?) ?? '';
      _loaded = true;
    });
    _status();
  }

  Future<void> _status() async {
    final st = await widget.bridge.getStatus();
    if (!mounted) return;
    setState(() {
      _mediaAccess = (st['media_access'] as bool?) ?? false;
      _ppnModel = (st['ppn_model'] as bool?) ?? false;
    });
  }

  Future<void> _put(Map<String, Object?> m) => widget.bridge.saveSettings(m);

  Widget _switchRow(String title, String sub, bool v, ValueChanged<bool> on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12.5)),
                ],
              ),
            ),
            Switch(
              value: v,
              activeColor: SiyaColors.cyanSoft,
              activeTrackColor: SiyaColors.purple.withOpacity(0.6),
              onChanged: on,
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SiyaPage(
      title: 'Features',
      child: !_loaded
          ? const Center(child: CircularProgressIndicator(color: SiyaColors.cyan))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                SiyaCard(
                  child: Column(
                    children: [
                      _switchRow('Hey Siya (hamesha on)',
                          _wake ? 'Background mein "Hey Siya" sun rahi hai' : 'Band - "Hey Siya" bolkar jagao', _wake, (v) {
                        setState(() => _wake = v);
                        _put({'wake_word_enabled': v});
                      }),
                      _switchRow('AI Browser', _aiBrowser ? 'Siya ko browser chalane do' : 'Band', _aiBrowser, (v) {
                        setState(() => _aiBrowser = v);
                        _put({'ai_browser_enabled': v});
                      }),
                      _switchRow('Screen on rakho', _keepAwake ? 'AI chalne tak screen band nahi hogi' : 'Screen normal timeout par band hogi',
                          _keepAwake, (v) {
                        setState(() => _keepAwake = v);
                        _put({'keep_screen_on': v});
                      }),
                      _switchRow('Call detect', _callDetect ? 'Call aane par Siya naam bolegi' : 'Band - call track nahi hoti',
                          _callDetect, (v) {
                        setState(() => _callDetect = v);
                        _put({'call_detect_enabled': v});
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SiyaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Awaaz focus', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Sirf aapki awaaz sune, peeche ki TV / bheed ki nahi',
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12.5)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: const {'off': 'Off', 'normal': 'Normal', 'strict': 'Strict'}.entries.map((e) {
                          final sel = _focus == e.key;
                          return ChoiceChip(
                            label: Text(e.value),
                            selected: sel,
                            onSelected: (_) {
                              setState(() => _focus = e.key);
                              _put({'voice_focus': e.key});
                            },
                            selectedColor: SiyaColors.cyan.withOpacity(0.35),
                            backgroundColor: const Color(0xFF071826),
                            labelStyle: const TextStyle(color: Colors.white),
                            side: BorderSide(color: SiyaColors.cyan.withOpacity(0.35)),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SiyaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('"Hey Siya" engine (offline)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        _ppnModel
                            ? 'hey_siya.ppn mil gayi. AccessKey daalo.'
                            : 'hey_siya.ppn abhi app mein nahi hai (assets folder mein daalo) - tab tak purana wake word chalega.',
                        style: TextStyle(color: _ppnModel ? SiyaColors.ok : Colors.white.withOpacity(0.55), fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ppnKey,
                        obscureText: _hideKey,
                        style: const TextStyle(color: Colors.white),
                        onSubmitted: (v) => _put({'picovoice_key': v}),
                        onEditingComplete: () => _put({'picovoice_key': _ppnKey.text}),
                        decoration: siyaInput('Picovoice AccessKey', Icons.key_outlined).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_hideKey ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white54),
                            onPressed: () => setState(() => _hideKey = !_hideKey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SiyaButton(label: 'Key save karo', outlined: true, onTap: () async {
                        await _put({'picovoice_key': _ppnKey.text});
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Key save ho gayi')));
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SiyaCard(
                  child: GestureDetector(
                    onTap: () => widget.bridge.openNotificationAccess(),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        const Icon(Icons.music_note_outlined, color: SiyaColors.cyanSoft),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Media access', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                _mediaAccess ? 'ON - Siya dekh sakti hai kya chal raha hai' : 'Off - tap karke "Siya" ko allow karo',
                                style: TextStyle(color: _mediaAccess ? SiyaColors.ok : Colors.white.withOpacity(0.55), fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
