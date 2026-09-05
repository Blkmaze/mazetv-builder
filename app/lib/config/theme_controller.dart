import 'package:flutter/material.dart';
import '../services/storage.dart';
import 'branding.dart';

/// Lets the viewer override the build's baked-in accent color from
/// Settings, without needing a new APK. Falls back to whatever the
/// builder set (Branding.I.primaryColor) until they change it.
class ThemeController {
  static final ValueNotifier<Color> primaryColor = ValueNotifier(Branding.I.primaryColor);

  static Future<void> load() async {
    final saved = await Storage.colorOverride();
    if (saved != null) primaryColor.value = Color(saved);
  }

  static Future<void> setColor(Color c) async {
    primaryColor.value = c;
    await Storage.setColorOverride(c.value);
  }

  static Future<void> resetToDefault() async {
    primaryColor.value = Branding.I.primaryColor;
    await Storage.clearColorOverride();
  }
}
