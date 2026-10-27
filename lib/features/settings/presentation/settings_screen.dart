import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/config/transit_config.dart';
import '../../stops_and_lines/presentation/feed_update_controller.dart';
import 'theme_mode_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeControllerProvider);
    final feedState = ref.watch(feedUpdateControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
            child: Text(
              l10n.settingsIntro,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    l10n.themePreferenceTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.themePreferenceDescription,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  themeMode.when(
                    data: (mode) => SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: const Icon(Symbols.light_mode_rounded),
                          label: Text(l10n.themeLight),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: const Icon(Symbols.dark_mode_rounded),
                          label: Text(l10n.themeDark),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Symbols.settings_suggest_rounded),
                          label: Text(l10n.themeSystem),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (selection) {
                        unawaited(
                          ref
                              .read(themeModeControllerProvider.notifier)
                              .setThemeMode(selection.first),
                        );
                      },
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Text(l10n.settingsLoadError),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Symbols.privacy_tip_rounded),
              title: Text(l10n.privacyTitle),
              trailing: const Icon(Symbols.chevron_right_rounded),
              onTap: () => context.push('/settings/privacy'),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: feedState.when(
                loading: () => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.transitDataTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(l10n.transitDataLoading),
                  ],
                ),
                error: (error, stack) =>
                    Text('${l10n.transitDataTitle}: ${l10n.transitNoData}'),
                data: (feed) {
                  final info = feed.feed?.feedInfo;
                  final valid = feed.status.validUntil;
                  final updated = feed.status.downloadedAt;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.transitDataTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${l10n.transitSourceLabel}: ${feed.status.source.isEmpty ? l10n.transitNoData : feed.status.source}',
                      ),
                      Text(
                        '${l10n.transitVersionLabel}: ${feed.status.version.isEmpty ? l10n.transitUnknownValue : feed.status.version}',
                      ),
                      Text(
                        '${l10n.transitUpdatedLabel}: ${updated == null ? l10n.transitUpdatedAtNone : updated.toLocal().toString().substring(0, 16)}',
                      ),
                      Text(
                        '${l10n.transitValidityLabel}: ${valid == null ? l10n.transitUnknownValue : (feed.status.stale ? l10n.transitExpired : l10n.transitCurrent)}',
                      ),
                      if (feed.feed != null ||
                          feed.status.stopCount > 0 ||
                          feed.status.routeCount > 0)
                        Text(
                          l10n.transitCounts(
                            feed.status.stopCount,
                            feed.status.routeCount,
                          ),
                        ),
                      if (feed.phase == FeedUpdatePhase.downloading ||
                          feed.phase == FeedUpdatePhase.processing)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(
                            value: feed.phase == FeedUpdatePhase.processing
                                ? feed.progress
                                : null,
                          ),
                        ),
                      if (feed.status.synthetic || (info?.synthetic ?? false))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.transitDemoNotice,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (feed.phase == FeedUpdatePhase.offline)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.transitNoSource,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (feed.phase == FeedUpdatePhase.errorWithOldData)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.transitUpdateError,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: feed.phase == FeedUpdatePhase.downloading
                              ? null
                              : () => ref
                                    .read(feedUpdateControllerProvider.notifier)
                                    .updateNow(),
                          icon: const Icon(Symbols.refresh_rounded),
                          label: Text(l10n.transitUpdateNow),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.transitAttributionLabel}: ${transitConfig.attribution}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${l10n.transitLicenseLabel}: ${transitConfig.license}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (kDebugMode)
            Card(
              child: ListTile(
                leading: const Icon(Symbols.palette_rounded),
                title: Text(l10n.debugThemeSample),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => context.push('/debug/theme'),
              ),
            ),
        ],
      ),
    );
  }
}
