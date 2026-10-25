import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rumbo/features/settings/presentation/theme_mode_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'theme selection alternates and persists between app containers',
    () async {
      final firstLaunch = ProviderContainer();
      addTearDown(firstLaunch.dispose);

      expect(
        await firstLaunch.read(themeModeControllerProvider.future),
        ThemeMode.system,
      );

      final controller = firstLaunch.read(themeModeControllerProvider.notifier);
      await controller.setThemeMode(ThemeMode.light);
      expect(
        await firstLaunch.read(themeModeControllerProvider.future),
        ThemeMode.light,
      );

      await controller.setThemeMode(ThemeMode.dark);
      expect(
        await firstLaunch.read(themeModeControllerProvider.future),
        ThemeMode.dark,
      );

      final nextLaunch = ProviderContainer();
      addTearDown(nextLaunch.dispose);
      expect(
        await nextLaunch.read(themeModeControllerProvider.future),
        ThemeMode.dark,
      );
    },
  );
}
