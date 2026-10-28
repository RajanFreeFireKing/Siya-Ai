import 'package:flutter/material.dart';

import '../bridge/siya_bridge.dart';
import '../theme.dart';

Future<void> showThemedPermissionSheet(
  BuildContext context,
  SiyaBridge bridge, {
  VoidCallback? onAllowed,
}) {
  final accent = SiyaTheme.accent.value;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PermissionExplanationSheet(
      bridge: bridge,
      accent: accent,
      onAllowed: onAllowed,
    ),
  );
}

class _PermissionExplanationSheet extends StatelessWidget {
  const _PermissionExplanationSheet({
    required this.bridge,
    required this.accent,
    this.onAllowed,
  });

  final SiyaBridge bridge;
  final Color accent;
  final VoidCallback? onAllowed;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top drag indicator
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6C8D1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header Row
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent.withOpacity(0.24), accent.withOpacity(0.08)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.verified_user_rounded, color: accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Permissions Zaroori Hain ✨',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2A1C25),
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Siya AI ke features smoothly run karne ke liye',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text(
                'Aapka privacy aur data 100% surakshit hai. System permissions sirf in zaroori kamo ke liye use hoti hain:',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF5A4C56),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),

              // Permissions List
              _permItem(
                icon: Icons.mic_rounded,
                title: 'Microphone & Wake Word',
                desc: 'Voice commands sunne aur "Hey Siya" wake word detect karne ke liye.',
              ),
              const SizedBox(height: 10),

              _permItem(
                icon: Icons.phone_in_talk_rounded,
                title: 'Phone & Contacts',
                desc: 'Papa, Dost aur nicknames se 100% accurate direct call lagane ke liye.',
              ),
              const SizedBox(height: 10),

              _permItem(
                icon: Icons.location_on_rounded,
                title: 'Smart Location',
                desc: 'Live weather, aas-paas ki jagah aur interactive map view ke liye.',
              ),
              const SizedBox(height: 10),

              _permItem(
                icon: Icons.sms_rounded,
                title: 'SMS & Kharcha Ledger',
                desc: 'Bank aur UPI transaction se daily kharcha ledger banane ke liye.',
              ),
              const SizedBox(height: 20),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await bridge.requestPermissions();
                    onAllowed?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 5,
                  ),
                  child: const Text(
                    'Theek Hai, Allow Karein 👍',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Abhi Nahi',
                    style: TextStyle(
                      color: Color(0xFF8A7B85),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2A1C25),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B5C67),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
