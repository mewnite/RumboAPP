import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/line_chip.dart';
import '../../../features/favorites/domain/favorite.dart';
import '../../../features/favorites/presentation/favorites_controller.dart';
import '../../../features/map/data/connectivity_provider.dart';
import '../../../features/map/presentation/live_buses_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/sqflite_transit_repository.dart';
import '../data/transit_arrivals_source.dart';
import '../data/transit_database.dart';
import '../domain/transit_models.dart';

class StopDetailsData {
  const StopDetailsData({required this.routes, required this.arrivals});

  final List<Route> routes;
  final List<StopArrival> arrivals;
}

final stopDetailsProvider = FutureProvider.family<StopDetailsData, String>((
  ref,
  stopId,
) async {
  final database = TransitDatabase();
  final db = await database.open();
  try {
    final repository = SqfliteTransitRepository(() async => db);
    final routes = await repository.routesForStop(stopId);
    final liveState = ref.read(liveBusesControllerProvider);
    final livePositions = liveState.lastUpdatedAt == null
        ? null
        : liveState.positions;
    final arrivals = await TransitArrivalsSource(
      repository,
      livePositions: livePositions,
    ).arrivalsForStop(stopId, DateTime.now(), limit: 8);
    return StopDetailsData(routes: routes, arrivals: arrivals);
  } finally {
    await db.close();
  }
});

class StopDetailsSheet extends ConsumerWidget {
  const StopDetailsSheet({
    required this.stop,
    required this.onHowToGetThere,
    this.onRouteSelected,
    super.key,
  });

  final Stop stop;
  final VoidCallback onHowToGetThere;
  final ValueChanged<Route>? onRouteSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final details = ref.watch(stopDetailsProvider(stop.id));
    final isOffline =
        ref.watch(networkAvailableProvider).asData?.value == false;
    final favorites =
        ref.watch(favoritesControllerProvider).asData?.value ??
        const <Favorite>[];
    Favorite? savedFavorite;
    for (final favorite in favorites) {
      if (favorite.type == FavoriteType.stop && favorite.id == stop.id) {
        savedFavorite = favorite;
        break;
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stop.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                l10n.stopDetailCode(stop.code.isEmpty ? stop.id : stop.code),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (isOffline) ...[
                const SizedBox(height: 12),
                _StatusMessage(
                  icon: Symbols.wifi_off_rounded,
                  text: l10n.stopDetailOffline,
                ),
              ],
              const SizedBox(height: 20),
              Text(
                l10n.stopDetailRoutes,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              details.when(
                loading: () => const _DetailsLoading(),
                error: (error, _) => _DetailsError(
                  message: l10n.stopDetailError(error.toString()),
                  onRetry: () => ref.invalidate(stopDetailsProvider(stop.id)),
                ),
                data: (data) => data.routes.isEmpty
                    ? Text(l10n.mapStopNoRoutes)
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final route in data.routes)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: onRouteSelected == null
                                  ? null
                                  : () => onRouteSelected!(route),
                              child: LineChip(
                                label: route.shortName.isEmpty
                                    ? route.id
                                    : route.shortName,
                                backgroundColor: _routeColor(route),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.stopDetailArrivals,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              details.when(
                loading: () => const _DetailsLoading(),
                error: (error, _) => const SizedBox.shrink(),
                data: (data) => data.arrivals.isEmpty
                    ? Text(l10n.stopDetailNoService)
                    : Column(
                        children: [
                          for (final arrival in data.arrivals.take(8))
                            _ArrivalRow(arrival: arrival),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    key: ValueKey('favorite-stop-${stop.id}'),
                    onPressed: () =>
                        unawaited(_toggleFavorite(ref, stop, savedFavorite)),
                    icon: Icon(
                      savedFavorite == null
                          ? Symbols.favorite_border_rounded
                          : Symbols.favorite_rounded,
                      fill: savedFavorite == null ? 0 : 1,
                    ),
                    label: Text(
                      savedFavorite == null
                          ? l10n.stopFavoriteSave
                          : l10n.stopFavoriteRemove,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onHowToGetThere,
                    icon: const Icon(Symbols.directions_rounded),
                    label: Text(l10n.stopHowToGetThere),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _toggleFavorite(
  WidgetRef ref,
  Stop stop,
  Favorite? savedFavorite,
) async {
  final controller = ref.read(favoritesControllerProvider.notifier);
  if (savedFavorite != null) {
    await controller.remove(savedFavorite);
    return;
  }
  await controller.add(
    Favorite(
      id: stop.id,
      type: FavoriteType.stop,
      name: stop.name,
      latitude: stop.latitude,
      longitude: stop.longitude,
    ),
  );
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({required this.arrival});

  final StopArrival arrival;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seconds = arrival.departureTime.difference(DateTime.now()).inSeconds;
    final minutes = (seconds / 60).ceil().clamp(0, 999);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: LineChip(
        label: arrival.routeLabel,
        backgroundColor: AppColors.deepBlue,
      ),
      title: Text(arrival.destination),
      subtitle: Text(
        arrival.isLive
            ? l10n.stopArrivalLiveEstimated(minutes)
            : l10n.stopArrivalEstimated(minutes),
      ),
    );
  }
}

class _DetailsLoading extends StatelessWidget {
  const _DetailsLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _DetailsError extends StatelessWidget {
  const _DetailsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Symbols.refresh_rounded),
          label: Text(l10n.actionRetry),
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ],
  );
}

Color _routeColor(Route route) {
  final hex = route.color.replaceFirst('#', '');
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return AppColors.deepBlue;
  }
  return Color(int.parse('FF$hex', radix: 16));
}
