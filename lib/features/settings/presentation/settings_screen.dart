import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/config/transit_config.dart';
import '../../stops_and_lines/presentation/feed_update_controller.dart';
import '../../stops_and_lines/presentation/transit_status_providers.dart';
import '../../trip_planner/presentation/walking_red_status_provider.dart';
import 'theme_mode_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeControllerProvider);
    final feedState = ref.watch(feedUpdateControllerProvider);
    final redStatus = ref.watch(walkingRedStatusProvider);
    final localTransitStatus = ref.watch(transitLocalStatusProvider);
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final bodyStyle = theme.textTheme.bodyMedium!.copyWith(color: onSurface);
    final secondaryBodyStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsScreenTitle)),
      body: DefaultTextStyle(
        style: bodyStyle,
        child: ListView(
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onSurface,
                      ),
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
                            icon: Icon(
                              Symbols.light_mode_rounded,
                              color: onSurface,
                            ),
                            label: Text(
                              l10n.themeLight,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: onSurface,
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(
                              Symbols.dark_mode_rounded,
                              color: onSurface,
                            ),
                            label: Text(
                              l10n.themeDark,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: onSurface,
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(
                              Symbols.settings_suggest_rounded,
                              color: onSurface,
                            ),
                            label: Text(
                              l10n.themeSystem,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: onSurface,
                              ),
                            ),
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
                      error: (error, stackTrace) =>
                          Text(l10n.settingsLoadError),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: Icon(
                  Symbols.privacy_tip_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  l10n.privacyTitle,
                  style: theme.textTheme.bodyLarge?.copyWith(color: onSurface),
                ),
                trailing: Icon(
                  Symbols.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(l10n.transitDataLoading, style: bodyStyle),
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${l10n.transitSourceLabel}: ${feed.status.source.isEmpty ? l10n.transitNoData : feed.status.source}',
                          style: bodyStyle,
                        ),
                        Text(
                          '${l10n.transitVersionLabel}: ${feed.status.version.isEmpty ? l10n.transitUnknownValue : feed.status.version}',
                          style: bodyStyle,
                        ),
                        Text(
                          '${l10n.transitUpdatedLabel}: ${updated == null ? l10n.transitUpdatedAtNone : updated.toLocal().toString().substring(0, 16)}',
                          style: bodyStyle,
                        ),
                        Text(
                          '${l10n.transitValidityLabel}: ${valid == null ? l10n.transitUnknownValue : (feed.status.stale ? l10n.transitExpired : l10n.transitCurrent)}',
                          style: bodyStyle,
                        ),
                        if (feed.feed != null ||
                            feed.status.stopCount > 0 ||
                            feed.status.routeCount > 0)
                          Text(
                            l10n.transitCounts(
                              feed.status.stopCount,
                              feed.status.routeCount,
                            ),
                            style: bodyStyle,
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
                              style: secondaryBodyStyle,
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
                                : () async {
                                    await ref
                                        .read(
                                          feedUpdateControllerProvider.notifier,
                                        )
                                        .updateNow();
                                    ref.invalidate(transitLocalStatusProvider);
                                  },
                            icon: const Icon(Symbols.refresh_rounded),
                            label: Text(l10n.transitUpdateNow),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${l10n.transitAttributionLabel}: ${transitConfig.attribution}',
                          style: secondaryBodyStyle,
                        ),
                        Text(
                          '${l10n.transitLicenseLabel}: ${transitConfig.license}',
                          style: secondaryBodyStyle,
                        ),
                      ],
                    );
                  },
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
                      l10n.transitDiagnosticsTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${l10n.walkingRedTitle}: '
                      '${_redStatusText(l10n, redStatus)}',
                      style: bodyStyle,
                    ),
                    const SizedBox(height: 8),
                    localTransitStatus.when(
                      loading: () => Text(
                        l10n.transitDiagnosticsLoading,
                        style: secondaryBodyStyle,
                      ),
                      error: (error, stackTrace) => Text(
                        l10n.settingsLoadError,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      data: (status) {
                        final database = status.database;
                        final validUntil = database.feedValidUntil;
                        final lastCheck = status.lastCheckMilliseconds;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l10n.transitVersionLabel}: '
                              '${database.feedVersion ?? l10n.transitUnknownValue}',
                              style: bodyStyle,
                            ),
                            Text(
                              '${l10n.transitValidityLabel}: '
                              '${validUntil == null ? l10n.transitUnknownValue : _formatDate(validUntil)}',
                              style: bodyStyle,
                            ),
                            Text(
                              '${l10n.transitSchemaVersionLabel}: '
                              '${database.schemaVersion}',
                              style: bodyStyle,
                            ),
                            Text(
                              '${l10n.transitDbSizeLabel}: '
                              '${_formatDatabaseSize(database.fileSizeBytes, l10n)}',
                              style: bodyStyle,
                            ),
                            Text(
                              '${l10n.transitVariantsWithIdLabel}: '
                              '${database.variantsWithExternalId}/${database.variantCount}',
                              style: bodyStyle,
                            ),
                            Text(
                              '${l10n.transitLastCheckLabel}: '
                              '${lastCheck == null ? l10n.transitUpdatedAtNone : _formatDateTime(DateTime.fromMillisecondsSinceEpoch(lastCheck))}',
                              style: secondaryBodyStyle,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.transitDiagnosticsLocalNotice,
                      style: secondaryBodyStyle,
                    ),
                  ],
                ),
              ),
            ),
            if (kDebugMode)
              Card(
                child: ListTile(
                  leading: const Icon(Symbols.palette_rounded),
                  title: Text(
                    l10n.debugThemeSample,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: onSurface,
                    ),
                  ),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/debug/theme'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _redStatusText(
    AppLocalizations l10n,
    AsyncValue<WalkingRedState> status,
  ) => status.when(
    loading: () => l10n.walkingRedLoading,
    error: (error, stackTrace) =>
        _walkingUnavailableText(l10n, l10n.walkingRedMotivoWorkerFallo),
    data: (value) => switch (value.status) {
      WalkingRedStatus.cargada => l10n.walkingRedCargada,
      WalkingRedStatus.seedAusente => _walkingUnavailableText(
        l10n,
        l10n.walkingRedMotivoSeedAusente,
      ),
      WalkingRedStatus.workerFallo => _walkingUnavailableText(
        l10n,
        l10n.walkingRedMotivoWorkerFallo,
      ),
      WalkingRedStatus.snapNulo => _walkingUnavailableText(
        l10n,
        l10n.walkingRedMotivoSnapNulo,
      ),
    },
  );

  String _walkingUnavailableText(AppLocalizations l10n, String reason) =>
      '${l10n.walkingRedIndisponible} '
      '(${l10n.walkingRedMotivoPrefix}$reason)';

  String _formatDate(DateTime value) =>
      value.toLocal().toIso8601String().substring(0, 10);

  String _formatDateTime(DateTime value) =>
      value.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ');

  String _formatDatabaseSize(int bytes, AppLocalizations l10n) {
    if (bytes <= 0) return l10n.transitUnknownValue;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
