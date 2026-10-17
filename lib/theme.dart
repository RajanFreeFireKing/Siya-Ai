import 'package:flutter/material.dart';

/// Purana dark palette - baaki screens (Settings, People, Memory...) abhi isi ko use karte hain,
/// isliye ye constants jaise the waise rakhe hain.
class SiyaColors {
  static const Color bg = Color(0xFF070414);
  static const Color card = Color(0xFF120B27);
  static const Color cyan = Color(0xFF9B6BFF);
  static const Color cyanSoft = Color(0xFFC7A7FF);
  static const Color blue = Color(0xFF6E4BFF);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color violet = Color(0xFFB58CFF);
  static const Color ok = Color(0xFF00E676);
  static const Color warn = Color(0xFFFFA726);
  static const Color bad = Color(0xFFFF5252);
}

/// NAYA design (pink / orange gradient) ke saare colors ek jagah.
class SiyaLight {
  static const Color orange = Color(0xFF9A6BFF);
  static const Color orangeSoft = Color(0xFFC9B3FF);
  static const Color magenta = Color(0xFF6D35D4);
  static const Color violet = Color(0xFF9A65FF);
  static const Color pink = Color(0xFFB26BFF); // dots / gear / mic icon
  static const Color pinkDeep = Color(0xFF7844D6);
  static const Color blob = Color(0xFF8F5CFF); // "I'm listening" ka gola
  static const Color ink = Color(0xFFF5F0FF); // greeting text
  static const Color grey = Color(0xFFB3A8CC); // subtitle text
  static const Color pageBottom = Color(0xFF0B0618); // navigation bar ka rang
}

/// Home screen par status text dikhana hai ya nahi (purana flag, ab use nahi hota).
const bool kShowStatusText = false;
