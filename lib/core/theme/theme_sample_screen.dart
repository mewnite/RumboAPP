import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../widgets/line_chip.dart';
import 'app_colors.dart';

class ThemeSampleScreen extends StatelessWidget {
  const ThemeSampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    assert(
      kDebugMode,
      'The identity sample is only available in debug builds.',
    );
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.debugThemeSampleTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.debugPaletteTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _PaletteSwatch(
                        label: l10n.debugPaletteInk,
                        background: AppColors.ink,
                        foreground: AppColors.ivory,
                      ),
                      _PaletteSwatch(
                        label: l10n.debugPaletteIvory,
                        background: AppColors.ivory,
                        foreground: AppColors.ink,
                      ),
                      _PaletteSwatch(
                        label: l10n.debugPaletteRumbo,
                        background: AppColors.rumbo,
                        foreground: AppColors.surface,
                      ),
                      _PaletteSwatch(
                        label: l10n.debugPaletteLime,
                        background: AppColors.lime,
                        foreground: AppColors.ink,
                      ),
                      _PaletteSwatch(
                        label: l10n.debugPaletteSurface,
                        background: AppColors.surface,
                        foreground: AppColors.ink,
                      ),
                      _PaletteSwatch(
                        label: l10n.debugPaletteDarkSurface,
                        background: AppColors.darkSurface,
                        foreground: AppColors.ivory,
                      ),
                      _PaletteSwatch(
                        label: l10n.debugPaletteDarkElevated,
                        background: AppColors.darkElevatedSurface,
                        foreground: AppColors.ivory,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.debugTypographyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.debugBodyText,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.debugTypographyBody),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.debugLineChipsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      LineChip(label: 'A', backgroundColor: AppColors.rumbo),
                      LineChip(label: 'D', backgroundColor: AppColors.lime),
                      LineChip(label: '142', backgroundColor: AppColors.ink),
                      LineChip(
                        label: '174',
                        backgroundColor: AppColors.surface,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StateSwatch(
                        label: l10n.debugAccentLabel,
                        background: AppColors.lime,
                        foreground: AppColors.ink,
                      ),
                      _StateSwatch(
                        label: l10n.debugErrorLabel,
                        background: colorScheme.error,
                        foreground: colorScheme.onError,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 76,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.bottomLeft,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}

class _StateSwatch extends StatelessWidget {
  const _StateSwatch({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: foreground),
      ),
    );
  }
}
