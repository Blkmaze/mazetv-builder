import 'package:flutter/material.dart';
import '../services/storage.dart';
import 'branding.dart';

/// One named look: accent + background.
class ThemePreset {
  final String name;
  final Color accent;
  final Color background;
  const ThemePreset(this.name, this.accent, this.background);
}

/// Lets the viewer change the look from Settings without a new APK: the
/// accent color (buttons, highlights) and the background. Falls back to the
/// builder's baked-in accent on a dark background until changed.
class ThemeController {
  static const defaultBackground = Color(0xFF0E0E10);

  static final ValueNotifier<Color> primaryColor = ValueNotifier(Branding.I.primaryColor);
  static final ValueNotifier<Color> background = ValueNotifier(defaultBackground);

  static const presets = <ThemePreset>[
    ThemePreset('Maze Red', Color(0xFFE50914), Color(0xFF0E0E10)),
    ThemePreset('Ghost Purple', Color(0xFF7B61FF), Color(0xFF0F1020)),
    ThemePreset('HyDr0 Blue', Color(0xFF00B4FF), Color(0xFF0A0E16)),
    ThemePreset('Emerald', Color(0xFF22C55E), Color(0xFF0B1210)),
    ThemePreset('Amber', Color(0xFFF59E0B), Color(0xFF14110A)),
    ThemePreset('Slate', Color(0xFF94A3B8), Color(0xFF111418)),
  ];

  static Future<void> load() async {
    final saved = await Storage.colorOverride();
    if (saved != null) primaryColor.value = Color(saved);
    final bg = await Storage.bgOverride();
    if (bg != null) background.value = Color(bg);
  }

  static Future<void> setColor(Color c) async {
    primaryColor.value = c;
    await Storage.setColorOverride(c.value);
  }

  static Future<void> setBackground(Color c) async {
    background.value = c;
    await Storage.setBgOverride(c.value);
  }

  static Future<void> applyPreset(ThemePreset p) async {
    await setColor(p.accent);
    await setBackground(p.background);
  }

  static Future<void> resetToDefault() async {
    primaryColor.value = Branding.I.primaryColor;
    background.value = defaultBackground;
    await Storage.clearColorOverride();
    await Storage.clearBgOverride();
  }
}
