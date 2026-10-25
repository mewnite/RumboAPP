import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/presentation/theme_mode_provider.dart';
import 'l10n/generated/app_localizations.dart';

class RumboApp extends ConsumerWidget {
  const RumboApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedThemeMode = ref.watch(themeModeControllerProvider);
    final themeMode = savedThemeMode.asData?.value ?? ThemeMode.system;

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('es', 'UY'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
