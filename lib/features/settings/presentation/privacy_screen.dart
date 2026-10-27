import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/map_config.dart';
import '../../../core/config/transit_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../search/presentation/search_controller.dart';
import '../data/local_data_repository.dart';
import 'privacy_preferences.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final remoteSearch = ref.watch(remotePlaceSearchEnabledProvider);
    final liveBuses = ref.watch(liveBusesEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionCard(
            title: l10n.privacyNetworkTitle,
            icon: Symbols.public_rounded,
            children: [
              _InfoRow(
                title: l10n.privacyMapTitle,
                body: '${MapConfig.providerName}: ${l10n.privacyMapBody}',
              ),
              _InfoRow(
                title: l10n.privacyTransitTitle,
                body: l10n.privacyTransitBody(
                  transitConfig.url.isEmpty
                      ? l10n.transitDemoNotice
                      : l10n.privacyConfiguredSource,
                ),
              ),
              _InfoRow(
                title: l10n.privacySearchTitle,
                body: l10n.privacySearchBody,
              ),
              _InfoRow(
                title: l10n.privacyLiveTitle,
                body: l10n.privacyLiveBody,
              ),
              const Divider(),
              Text(
                l10n.privacyIpNotice,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          _SectionCard(
            title: l10n.privacyLocalTitle,
            icon: Symbols.phonelink_lock_rounded,
            children: [
              _InfoRow(
                title: l10n.privacyLocalGpsTitle,
                body: l10n.privacyLocalGpsBody,
              ),
              _InfoRow(
                title: l10n.privacyLocalDataTitle,
                body: l10n.privacyLocalDataBody,
              ),
            ],
          ),
          _SectionCard(
            title: l10n.privacyControlsTitle,
            icon: Symbols.tune_rounded,
            children: [
              remoteSearch.when(
                data: (enabled) => SwitchListTile(
                  key: const ValueKey('remote-place-search-setting'),
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  title: Text(l10n.remotePlaceSearchTitle),
                  subtitle: Text(l10n.remotePlaceSearchDescription),
                  onChanged: (value) => unawaited(
                    ref
                        .read(remotePlaceSearchEnabledProvider.notifier)
                        .setEnabled(value),
                  ),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, stack) => Text(l10n.settingsLoadError),
              ),
              liveBuses.when(
                data: (enabled) => SwitchListTile(
                  key: const ValueKey('live-buses-setting'),
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  title: Text(l10n.privacyLiveSwitchTitle),
                  subtitle: Text(l10n.privacyLiveSwitchDescription),
                  onChanged: (value) => unawaited(
                    ref
                        .read(liveBusesEnabledProvider.notifier)
                        .setEnabled(value),
                  ),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, stack) => Text(l10n.settingsLoadError),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Symbols.delete_sweep_rounded),
                label: Text(l10n.privacyClearButton),
                onPressed: () => _confirmClear(context, ref),
              ),
            ],
          ),
          _SectionCard(
            title: l10n.privacyAboutTitle,
            icon: Symbols.info_rounded,
            children: [
              _InfoRow(
                title: l10n.privacyAttributionTitle,
                body: '${MapConfig.attribution}. ${l10n.privacyDagTodo}',
              ),
              _InfoRow(
                title: l10n.privacyFontTitle,
                body: l10n.privacyFontBody,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.privacyLicensesButton),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: l10n.appTitle,
                  applicationVersion: '1.0.0',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.privacyClearConfirmTitle),
        content: Text(l10n.privacyClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.privacyClearButton),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    try {
      await ref.read(localDataRepositoryProvider).clearUserData();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.privacyClearSuccess)));
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.privacyClearFailed)));
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon), const SizedBox(width: 10), Text(title)]),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(body, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
