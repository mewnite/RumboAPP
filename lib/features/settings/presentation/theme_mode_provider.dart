import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shared_preferences_theme_preference_repository.dart';
import '../domain/theme_preference_repository.dart';

final themePreferenceRepositoryProvider = Provider<ThemePreferenceRepository>(
  (ref) => SharedPreferencesThemePreferenceRepository(),
);

final themeModeControllerProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
      ThemeModeController.new,
    );

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() {
    return ref.watch(themePreferenceRepositoryProvider).loadThemeMode();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      await ref.read(themePreferenceRepositoryProvider).saveThemeMode(mode);
      state = AsyncData(mode);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
