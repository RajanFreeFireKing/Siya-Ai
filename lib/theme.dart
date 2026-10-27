import 'package:flutter/material.dart';

/// Purana dark palette - baaki screens (Settings, People, Memory...) abhi isi ko use karte hain,
/// isliye ye constants jaise the waise rakhe hain.
class SiyaColors {
  static const Color bg = Color(0xFF020A14);
  static const Color card = Color(0xFF0A1826);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color cyanSoft = Color(0xFF3EE6FF);
  static const Color blue = Color(0xFF2F6BFF);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color violet = Color(0xFFB58CFF);
  static const Color ok = Color(0xFF00E676);
  static const Color warn = Color(0xFFFFA726);
  static const Color bad = Color(0xFFFF5252);
}

/// NAYA design (pink / orange gradient) ke saare colors ek jagah.
class SiyaLight {
  static const Color orange = Color(0xFFFF9A4D);
  static const Color orangeSoft = Color(0xFFFFB877);
  static const Color magenta = Color(0xFFFF5CF2);
  static const Color violet = Color(0xFFD64DFF);
  static const Color pink = Color(0xFFF2279F); // dots / gear / mic icon
  static const Color pinkDeep = Color(0xFFE0168F);
  static const Color blob = Color(0xFFF45BB5); // "I'm listening" ka gola
  static const Color ink = Color(0xFF0F172A); // greeting text
  static const Color grey = Color(0xFF7C8596); // subtitle text
  static const Color pageBottom = Color(0xFFFFE9F4); // navigation bar ka rang
}

/// Home screen par status text dikhana hai ya nahi (purana flag, ab use nahi hota).
const bool kShowStatusText = false;

/// Shared, persisted accent color for the complete Siya AI app.
class SiyaTheme {
  SiyaTheme._();
  static const Color defaultAccent = Color(0xFFFF2A6D);
  static final ValueNotifier<Color> accent = ValueNotifier<Color>(defaultAccent);
  static Color parseAccent(Object? value) {
    if (value is int) return Color(value);
    if (value is! String) return defaultAccent;
    final raw = value.trim().replaceFirst('#', '').replaceFirst('0x', '');
    final parsed = int.tryParse(raw, radix: 16);
    if (parsed == null) return defaultAccent;
    return Color(raw.length == 6 ? 0xFF000000 | parsed : parsed);
  }
  static Future<void> loadFromSettings(Future<Map<String, dynamic>> Function() read) async {
    try {
      final settings = await read();
      if (settings['app_accent_color'] != null) {
        accent.value = parseAccent(settings['app_accent_color']);
      }
    } catch (_) {}
  }
  static Future<void> setAccent(Color color, Future<void> Function(Map<String, dynamic>) save) async {
    accent.value = color;
    await save({'app_accent_color': color.value});
  }
}
