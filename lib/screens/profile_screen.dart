import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';
import '../widgets/siya_ui.dart';

/// Profile: user ka naam aur prime contact. Settings se alag screen, apna Save button.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.bridge});

  final SiyaBridge bridge;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _primeName = TextEditingController();
  final _primeNumber = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _primeName.dispose();
    _primeNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await widget.bridge.getSettings();
    if (!mounted) return;
    setState(() {
      _name.text = (s['user_name'] as String?) ?? 'Sir';
      _primeName.text = (s['prime_name'] as String?) ?? '';
      _primeNumber.text = (s['prime_number'] as String?) ?? '';
      _loaded = true;
    });
  }

  Future<void> _pickContact() async {
    final r = await widget.bridge.pickContact();
    if (r == null || !mounted) return;
    setState(() {
      _primeName.text = r['name'] ?? '';
      _primeNumber.text = r['number'] ?? '';
    });
  }

  Future<void> _save() async {
    await widget.bridge.saveSettings({
      'user_name': _name.text,
      'prime_name': _primeName.text,
      'prime_number': _primeNumber.text,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = SiyaTheme.accent.value;
    return SiyaPage(
      title: 'Profile',
      child: !_loaded
          ? Center(child: CircularProgressIndicator(color: accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SiyaCard(
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [accent, Color.lerp(accent, Colors.white, 0.45)!]),
                          boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 18)],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _name.text.trim().isEmpty ? '?' : _name.text.trim()[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _name,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Color(0xFF1E232F)),
                        decoration: siyaInput('Your name', Icons.person_outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SiyaCard(
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _primeName,
                              style: const TextStyle(color: Color(0xFF1E232F)),
                              decoration: siyaInput('Prime contact', Icons.star_outline),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SiyaIconBtn(icon: Icons.contacts_outlined, onTap: _pickContact),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _primeNumber,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Color(0xFF1E232F)),
                        decoration: siyaInput('Prime number', Icons.phone_outlined),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SiyaButton(label: 'Save', onTap: _save),
              ],
            ),
    );
  }
}
