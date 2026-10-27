import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/line_chip.dart';
import '../../../features/favorites/domain/favorite.dart';
import '../../../features/favorites/presentation/favorites_controller.dart';
import '../../../features/map/data/connectivity_provider.dart';
import '../../../features/map/presentation/live_buses_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/sqflite_transit_repository.dart';
import '../data/transit_database.dart';
import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';

final transitRepositoryProvider = Provider<TransitRepository>((ref) {
  return SqfliteTransitRepository(() => TransitDatabase().open());
});

final lineVariantsProvider = FutureProvider.family<List<RouteVariant>, String>((
  ref,
  routeId,
) async {
  final repository = ref.watch(transitRepositoryProvider);
  return repository.variantsForRoute(routeId);
});

final variantStopsProvider = FutureProvider.family<List<Stop>, String>((
  ref,
  variantId,
) async {
  final repository = ref.watch(transitRepositoryProvider);
  return repository.stopsForVariant(variantId);
});

final variantDeparturesProvider = FutureProvider.family<List<DateTime>, String>(
  (ref, variantId) async {
    final repository = ref.watch(transitRepositoryProvider);
    return repository.upcomingDeparturesForVariant(variantId, DateTime.now());
  },
);

class LineDetailsSheet extends ConsumerStatefulWidget {
  const LineDetailsSheet({
    required this.route,
    this.initialVariantId,
    this.onVariantSelected,
    this.onStopSelected,
    this.onClose,
    super.key,
  });

  final Route route;
  final String? initialVariantId;
  final ValueChanged<RouteVariant>? onVariantSelected;
  final ValueChanged<Stop>? onStopSelected;
  final VoidCallback? onClose;

  @override
  ConsumerState<LineDetailsSheet> createState() => _LineDetailsSheetState();
}

class _LineDetailsSheetState extends ConsumerState<LineDetailsSheet> {
  String? _selectedVariantId;

  @override
  void initState() {
    super.initState();
    _selectedVariantId = widget.initialVariantId;
  }

  Color _routeColor(Route route) {
    final hex = route.color.replaceFirst('#', '');
    if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return AppColors.deepBlue;
  }

  Future<void> _toggleFavorite(
    WidgetRef ref,
    Route route,
    Favorite? savedFavorite,
  ) async {
    final controller = ref.read(favoritesControllerProvider.notifier);
    if (savedFavorite == null) {
      await controller.add(
        Favorite.line(
          id: route.id,
          name: route.shortName.isEmpty ? route.id : route.shortName,
        ),
      );
    } else {
      await controller.remove(savedFavorite);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isOffline =
        ref.watch(networkAvailableProvider).asData?.value == false;
    final variantsAsync = ref.watch(lineVariantsProvider(widget.route.id));
    final favorites =
        ref.watch(favoritesControllerProvider).asData?.value ??
        const <Favorite>[];

    Favorite? savedFavorite;
    for (final favorite in favorites) {
      if (favorite.type == FavoriteType.line &&
          favorite.id == widget.route.id) {
        savedFavorite = favorite;
        break;
      }
    }

    final liveState = ref.watch(liveBusesControllerProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: variantsAsync.when(
          loading: () => Semantics(
            label: l10n.mapRoutesLoading,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.error_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.lineDetailError(error.toString()),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(lineVariantsProvider(widget.route.id)),
                    icon: const Icon(Symbols.refresh_rounded),
                    label: Text(l10n.actionRetry),
                  ),
                ],
              ),
            ),
          ),
          data: (variants) {
            if (variants.isEmpty) {
              return EmptyState(
                icon: const Icon(Symbols.alt_route_rounded, size: 48),
                title: l10n.lineDetailNoVariants,
                message: l10n.lineDetailEmpty,
                footer: widget.onClose != null
                    ? TextButton(
                        onPressed: widget.onClose,
                        child: Text(l10n.actionClose),
                      )
                    : null,
              );
            }

            final activeVariant = variants.firstWhere(
              (v) => v.id == _selectedVariantId,
              orElse: () => variants.first,
            );

            // Filter live buses for this variant and route
            final livePositions = liveState.positions
                .where((bus) {
                  if (activeVariant.externalVariantId != null &&
                      bus.variantId == activeVariant.externalVariantId) {
                    return true;
                  }
                  final label = widget.route.shortName.toLowerCase();
                  return label.isNotEmpty &&
                      bus.lineLabel.toLowerCase() == label;
                })
                .toList(growable: false);

            final departuresAsync = ref.watch(
              variantDeparturesProvider(activeVariant.id),
            );
            final stopsAsync = ref.watch(
              variantStopsProvider(activeVariant.id),
            );

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Chip, title, close
                  Row(
                    children: [
                      LineChip(
                        label: widget.route.shortName.isEmpty
                            ? widget.route.id
                            : widget.route.shortName,
                        backgroundColor: _routeColor(widget.route),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.lineDetailTitle(
                                widget.route.shortName.isEmpty
                                    ? widget.route.id
                                    : widget.route.shortName,
                              ),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            if (widget.route.longName.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.route.longName,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onClose != null)
                        IconButton(
                          icon: const Icon(Symbols.close_rounded),
                          tooltip: l10n.actionClose,
                          onPressed: widget.onClose,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Offline notice
                  if (isOffline) ...[
                    _StatusMessage(
                      icon: Symbols.wifi_off_rounded,
                      text: l10n.lineDetailOffline,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Actions: Favorite toggle
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        key: ValueKey('favorite-line-${widget.route.id}'),
                        onPressed: () => unawaited(
                          _toggleFavorite(ref, widget.route, savedFavorite),
                        ),
                        icon: Icon(
                          savedFavorite == null
                              ? Symbols.favorite_border_rounded
                              : Symbols.favorite_rounded,
                          fill: savedFavorite == null ? 0 : 1,
                        ),
                        label: Text(
                          savedFavorite == null
                              ? l10n.lineFavoriteSave
                              : l10n.lineFavoriteRemove,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Variant selector
                  if (variants.length > 1) ...[
                    Text(
                      l10n.lineDetailVariant,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('variant-selector'),
                      initialValue: activeVariant.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        for (final variant in variants)
                          DropdownMenuItem<String>(
                            value: variant.id,
                            child: Text(
                              variant.destination.isNotEmpty
                                  ? l10n.lineDetailDirection(
                                      variant.destination,
                                    )
                                  : 'Variante ${variant.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (newVariantId) {
                        if (newVariantId == null) return;
                        setState(() => _selectedVariantId = newVariantId);
                        final selected = variants.firstWhere(
                          (v) => v.id == newVariantId,
                        );
                        widget.onVariantSelected?.call(selected);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Live buses section
                  Row(
                    children: [
                      Icon(
                        Symbols.directions_bus_rounded,
                        size: 20,
                        color: livePositions.isNotEmpty
                            ? AppColors.deepBlue
                            : Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.lineDetailLiveBusesCount(livePositions.length),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: livePositions.isNotEmpty
                                    ? AppColors.deepBlue
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                fontWeight: livePositions.isNotEmpty
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Upcoming departures
                  Text(
                    l10n.lineDetailUpcomingDepartures,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  departuresAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text(l10n.lineDetailError(e.toString())),
                    data: (departures) {
                      if (departures.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l10n.lineDetailNoDepartures,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final dep in departures.take(8))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                l10n.lineDetailDepartureEstimated(
                                  '${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}',
                                ),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Ordered list of stops
                  stopsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text(l10n.lineDetailError(e.toString())),
                    data: (stops) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l10n.lineDetailStopsTitle} (${stops.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          if (stops.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(l10n.lineDetailEmpty),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: stops.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final stop = stops[index];
                                return ListTile(
                                  key: ValueKey('line-stop-${stop.id}'),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: Text(
                                      '${index + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  title: Text(
                                    stop.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge,
                                  ),
                                  subtitle: stop.code.isNotEmpty
                                      ? Text(
                                          l10n.stopDetailCode(stop.code),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        )
                                      : null,
                                  trailing: const Icon(
                                    Symbols.chevron_right_rounded,
                                  ),
                                  onTap: () =>
                                      widget.onStopSelected?.call(stop),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
