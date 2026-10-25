import 'package:flutter/material.dart';

abstract interface class ThemePreferenceRepository {
  Future<ThemeMode> loadThemeMode();

  Future<void> saveThemeMode(ThemeMode mode);
}
