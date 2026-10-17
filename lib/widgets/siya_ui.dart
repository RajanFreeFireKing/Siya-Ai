import 'package:flutter/material.dart';

import '../theme.dart';
import 'aurora_background.dart';

/// Naye screens (Profile, Wallpaper, Location, User data) ke shared neon-style pieces.
class SiyaPage extends StatelessWidget {
  const SiyaPage({super.key, required this.title, required this.child, this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SiyaColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground()),
          SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    SiyaIconBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (r) =>
                            const LinearGradient(colors: [SiyaColors.cyanSoft, SiyaColors.violet]).createShader(r),
                        child: Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
          ),
        ],
      ),
    );
  }
}

class SiyaIconBtn extends StatelessWidget {
  const SiyaIconBtn({super.key, required this.icon, required this.onTap, this.danger = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF071826),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: (danger ? SiyaColors.bad : SiyaColors.cyan).withOpacity(0.6)),
          ),
          child: Icon(icon, color: danger ? SiyaColors.bad : Colors.white, size: 20),
        ),
      );
}

class SiyaCard extends StatelessWidget {
  const SiyaCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: SiyaColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SiyaColors.cyan.withOpacity(0.18)),
          boxShadow: [BoxShadow(color: SiyaColors.purple.withOpacity(0.06), blurRadius: 18)],
        ),
        child: child,
      );
}

class SiyaButton extends StatelessWidget {
  const SiyaButton({super.key, required this.label, required this.onTap, this.icon, this.outlined = false});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: outlined ? null : const LinearGradient(colors: [SiyaColors.cyan, SiyaColors.purple]),
              color: outlined ? const Color(0xFF071826) : null,
              border: outlined ? Border.all(color: SiyaColors.cyan.withOpacity(0.6)) : null,
              borderRadius: BorderRadius.circular(16),
              boxShadow: outlined ? null : [BoxShadow(color: SiyaColors.cyan.withOpacity(0.3), blurRadius: 14)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}

InputDecoration siyaInput(String label, IconData icon) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
      prefixIcon: Icon(icon, color: SiyaColors.cyanSoft.withOpacity(0.8), size: 20),
      filled: true,
      fillColor: const Color(0xFF071420),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: SiyaColors.cyan.withOpacity(0.2))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: SiyaColors.cyan.withOpacity(0.2))),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: SiyaColors.cyan, width: 1.4)),
    );
