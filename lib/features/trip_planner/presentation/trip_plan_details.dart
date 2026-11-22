import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/rumbo_components.dart';
import '../../../core/widgets/line_chip.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../stops_and_lines/data/transit_arrivals_source.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../../stops_and_lines/domain/transit_repository.dart';
import '../../stops_and_lines/presentation/transit_repository_provider.dart';
import '../domain/trip_planner.dart';

class TripPlanDetails extends StatelessWidget {
  const TripPlanDetails({
    required this.plan,
    required this.originName,
    required this.destinationName,
    required this.onChangeTrip,
    required this.onCloseTrip,
    this.onSwapTrip,
    this.activeTripIsActive = false,
    this.activeTripStopsRemaining,
    this.onStartActiveTrip,
    this.onStopActiveTrip,
    this.livePositions = const [],
    this.tripPlanShapes = const {},
    super.key,
  });

  final TripPlan plan;
  final String originName;
  final String destinationName;
  final VoidCallback onChangeTrip;
  final VoidCallback onCloseTrip;
  final VoidCallback? onSwapTrip;
  final bool activeTripIsActive;
  final int? activeTripStopsRemaining;
  final VoidCallback? onStartActiveTrip;
  final VoidCallback? onStopActiveTrip;
  final List<BusPosition> livePositions;
  final Map<String, Shape> tripPlanShapes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final steps = _timelineSteps(l10n);
    final firstTransitLegIndex = plan.legs.indexWhere(
      (leg) => leg.kind == TripLegKind.transit,
    );
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tripDetailTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: l10n.tripDetailClose,
              onPressed: onCloseTrip,
              icon: const Icon(Symbols.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const TripEndpointRail(height: 88),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      originName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      destinationName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('trip-detail-swap-endpoints'),
              tooltip: l10n.tripSwapEndpoints,
              onPressed: onSwapTrip,
              icon: const Icon(Symbols.swap_vert_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                l10n.tripPlanTimes(
                  _clock(plan.requestedDeparture),
                  _clock(plan.arrivalTime),
                ),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.tripPlanDuration(plan.duration.inMinutes),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _SummaryFact(
              icon: Symbols.directions_walk_rounded,
              label: l10n.tripPlanWalkingMinutes(_walkingMinutes(plan)),
            ),
            _SummaryFact(
              icon: Symbols.sync_alt_rounded,
              label: l10n.tripPlanTransfers(plan.transferCount),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < plan.legs.length; index++)
          if (plan.legs[index].kind == TripLegKind.transit)
            _TripLegEtaCard(
              plan: plan,
              legIndex: index,
              showLiveEta: index == firstTransitLegIndex,
              livePositions: livePositions,
              shapes: tripPlanShapes,
            ),
        for (var index = 0; index < steps.length; index++)
          _TimelineStepTile(
            step: steps[index],
            isLast: index == steps.length - 1,
            timeLabel: steps[index].estimated
                ? l10n.tripDetailEstimatedTime(_clock(steps[index].time))
                : _clock(steps[index].time),
          ),
        if (plan.totalWalkingMeters > 0) ...[
          const SizedBox(height: 4),
          Text(
            l10n.tripDetailWalkingTotal(plan.totalWalkingMeters.round()),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 8),
        Text(l10n.tripDetailWalkingApproximate, style: secondaryStyle),
        const SizedBox(height: 4),
        Text(l10n.tripDetailScheduleNotice, style: secondaryStyle),
        const SizedBox(height: 12),
        if (activeTripIsActive && activeTripStopsRemaining != null)
          TripProgressCard(
            title: l10n.activeTripNotificationTitle,
            subtitle: l10n.activeTripStopsRemaining(
              activeTripStopsRemaining!,
              destinationName,
            ),
          ),
        if (onStartActiveTrip != null || onStopActiveTrip != null)
          PrimaryActionButton(
            onPressed: activeTripIsActive
                ? onStopActiveTrip
                : onStartActiveTrip,
            icon: Icon(
              activeTripIsActive
                  ? Symbols.stop_circle_rounded
                  : Symbols.notifications_active_rounded,
            ),
            label: activeTripIsActive
                ? l10n.activeTripFinish
                : l10n.activeTripStart,
          ),
        if (onStartActiveTrip != null || onStopActiveTrip != null)
          const SizedBox(height: 8),
        SecondaryActionButton(
          onPressed: onChangeTrip,
          icon: const Icon(Symbols.edit_road_rounded),
          label: l10n.tripDetailChangeTrip,
        ),
      ],
    );
  }

  List<_TimelineStep> _timelineSteps(AppLocalizations l10n) {
    final steps = <_TimelineStep>[
      _TimelineStep(
        icon: Symbols.trip_origin_rounded,
        title: l10n.tripDetailStart,
        time: plan.requestedDeparture,
        isOrigin: true,
      ),
    ];

    for (final leg in plan.legs) {
      switch (leg.kind) {
        case TripLegKind.walking:
          steps.add(
            _TimelineStep(
              icon: Symbols.directions_walk_rounded,
              title: l10n.tripDetailWalkStep(leg.distanceMeters.round()),
              subtitle: _walkingSubtitle(l10n, leg),
              time: leg.arrivalTime,
              estimated: true,
            ),
          );
        case TripLegKind.waiting:
          break;
        case TripLegKind.transit:
          steps.add(
            _TimelineStep(
              icon: Symbols.directions_bus_rounded,
              title: l10n.tripDetailBoard(
                _lineLabel(l10n, leg),
                leg.fromStop?.name ?? l10n.tripDetailUnknownStop,
              ),
              transitLabel: _lineLabel(l10n, leg),
              subtitle: leg.headsign.trim().isEmpty
                  ? null
                  : l10n.tripDetailToward(leg.headsign.trim()),
              time: leg.departureTime,
              estimated: true,
            ),
          );
          steps.add(
            _TimelineStep(
              icon: Symbols.flag_rounded,
              title: l10n.tripDetailAlight(
                leg.toStop?.name ?? l10n.tripDetailUnknownStop,
              ),
              time: leg.arrivalTime,
              estimated: true,
              isAlight: true,
            ),
          );
      }
    }

    steps.add(
      _TimelineStep(
        icon: Symbols.location_on_rounded,
        title: l10n.tripDetailEnd,
        time: plan.arrivalTime,
        estimated: true,
        isDestination: true,
      ),
    );
    return steps;
  }

  String _walkingSubtitle(AppLocalizations l10n, TripLeg leg) {
    final from =
        leg.fromStop?.name ??
        (leg.fromLatitude != null ? originName : l10n.tripDetailUnknownStop);
    final to =
        leg.toStop?.name ??
        (leg.toLatitude != null ? destinationName : l10n.tripDetailUnknownStop);
    return l10n.tripDetailWalkInstructions(
      from,
      leg.distanceMeters.round(),
      to,
    );
  }

  String _lineLabel(AppLocalizations l10n, TripLeg leg) {
    final route = leg.route;
    if (route == null) return l10n.tripDetailUnknownStop;
    return route.shortName.isNotEmpty ? route.shortName : route.id;
  }
}

final _scheduledDeparturesProvider =
    FutureProvider.family<List<UpcomingDeparture>, String>((ref, stopId) {
      return ref
          .watch(transitRepositoryProvider)
          .upcomingDepartures(stopId, DateTime.now(), limit: 60);
    });

class _TripLegEtaCard extends ConsumerWidget {
  const _TripLegEtaCard({
    required this.plan,
    required this.legIndex,
    required this.showLiveEta,
    required this.livePositions,
    required this.shapes,
  });

  final TripPlan plan;
  final int legIndex;
  final bool showLiveEta;
  final List<BusPosition> livePositions;
  final Map<String, Shape> shapes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leg = plan.legs[legIndex];
    final stop = leg.fromStop;
    final route = leg.route;
    if (stop == null || route == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final line = route.shortName.isEmpty ? route.id : route.shortName;
    final estimate = estimateTripLegEta(
      plan: plan,
      legIndex: legIndex,
      livePositions: showLiveEta ? livePositions : const [],
      shapes: shapes,
      now: DateTime.now(),
      considerMissedBoarding: showLiveEta,
    );
    final theme = Theme.of(context);
    final nextDepartures = estimate.missedBoarding
        ? ref.watch(_scheduledDeparturesProvider(stop.id))
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.tripEtaBoardingStop(line, stop.name),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              !showLiveEta
                  ? l10n.tripEtaFutureScheduledTime(_clock(leg.departureTime))
                  : estimate.fromGps
                  ? estimate.minMinutes == estimate.maxMinutes
                        ? l10n.tripEtaGpsMinutes(estimate.minMinutes)
                        : l10n.tripEtaGpsRange(
                            estimate.minMinutes,
                            estimate.maxMinutes,
                          )
                  : l10n.tripEtaScheduledMinutes(estimate.minMinutes),
            ),
            if (estimate.fromGps && estimate.usesFallbackSpeed)
              Text(
                l10n.tripEtaFallback,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (estimate.missedBoarding) ...[
              const SizedBox(height: 8),
              Text(
                l10n.tripEtaMissed(
                  estimate.walkingMinutes,
                  estimate.minMinutes,
                ),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              nextDepartures!.when(
                data: (departures) {
                  final next = _nextScheduledDeparture(departures, leg);
                  return Text(
                    next == null
                        ? l10n.tripEtaNoNextScheduled
                        : l10n.tripEtaNextScheduled(_clock(next.departure)),
                  );
                },
                loading: () => Text(l10n.tripEtaNextLoading),
                error: (error, stackTrace) =>
                    Text(l10n.tripEtaNextError(error.toString())),
              ),
            ],
          ],
        ),
      ),
    );
  }

  UpcomingDeparture? _nextScheduledDeparture(
    List<UpcomingDeparture> departures,
    TripLeg leg,
  ) {
    final variantId = leg.variant?.id;
    final matching = departures.where(
      (departure) =>
          departure.trip.routeId == leg.route?.id &&
          (variantId == null || departure.trip.variantId == variantId) &&
          departure.departure.isAfter(leg.departureTime),
    );
    if (matching.isEmpty) return null;
    return matching.reduce(
      (first, second) =>
          first.departure.isBefore(second.departure) ? first : second,
    );
  }
}

class TripLegEtaEstimate {
  const TripLegEtaEstimate({
    required this.minMinutes,
    required this.maxMinutes,
    required this.fromGps,
    required this.usesFallbackSpeed,
    required this.walkingMinutes,
    required this.missedBoarding,
  });

  final int minMinutes;
  final int maxMinutes;
  final bool fromGps;
  final bool usesFallbackSpeed;
  final int walkingMinutes;
  final bool missedBoarding;
}

TripLegEtaEstimate estimateTripLegEta({
  required TripPlan plan,
  required int legIndex,
  required List<BusPosition> livePositions,
  required Map<String, Shape> shapes,
  required DateTime now,
  bool considerMissedBoarding = true,
}) {
  final leg = plan.legs[legIndex];
  final stop = leg.fromStop;
  final variant = leg.variant;
  final shape = variant == null ? null : shapes[variant.id] ?? leg.shape;
  ({int min, int max, bool fallback})? liveEstimate;
  if (stop != null && variant?.externalVariantId != null && shape != null) {
    for (final position in livePositions) {
      final age = now.difference(position.receivedAt);
      if (RealtimeMatcher.matchPositionToVariant(
                position,
                variant!,
                route: leg.route,
              ) ==
              null ||
          age.isNegative ||
          age > const Duration(seconds: 60)) {
        continue;
      }
      final range = estimateBusArrivalMinuteRange(
        position: position,
        stop: stop,
        shape: shape,
      );
      if (range == null) continue;
      final candidate = (
        min: range.$1,
        max: range.$2,
        fallback: position.speedKmh < 8,
      );
      if (liveEstimate == null || candidate.min < liveEstimate.min) {
        liveEstimate = candidate;
      }
    }
  }

  var walkingSeconds = 0;
  var hasWalkingLeg = false;
  var walkingIsReal = true;
  for (var index = legIndex - 1; index >= 0; index--) {
    final previous = plan.legs[index];
    if (previous.kind == TripLegKind.transit) break;
    if (previous.kind != TripLegKind.walking) continue;
    hasWalkingLeg = true;
    walkingIsReal &= !previous.approximate;
    final seconds = previous.arrivalTime
        .difference(previous.departureTime)
        .inSeconds;
    if (seconds > 0) walkingSeconds += seconds;
  }
  final walkingMinutes = (walkingSeconds / 60).ceil();
  final minMinutes =
      liveEstimate?.min ??
      math
          .max(0, (leg.departureTime.difference(now).inSeconds / 60).ceil())
          .toInt();
  final maxMinutes = liveEstimate?.max ?? minMinutes;
  final missedBoarding =
      considerMissedBoarding &&
      hasWalkingLeg &&
      walkingIsReal &&
      !leg.departureTime.isBefore(now.subtract(const Duration(minutes: 1))) &&
      minMinutes <= walkingMinutes + 1;
  return TripLegEtaEstimate(
    minMinutes: minMinutes,
    maxMinutes: maxMinutes,
    fromGps: liveEstimate != null,
    usesFallbackSpeed: liveEstimate?.fallback ?? false,
    walkingMinutes: walkingMinutes,
    missedBoarding: missedBoarding,
  );
}

class _TimelineStep {
  const _TimelineStep({
    required this.icon,
    required this.title,
    required this.time,
    this.subtitle,
    this.estimated = false,
    this.isOrigin = false,
    this.isDestination = false,
    this.transitLabel,
    this.isAlight = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final DateTime time;
  final bool estimated;
  final bool isOrigin;
  final bool isDestination;
  final String? transitLabel;
  final bool isAlight;
}

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({
    required this.step,
    required this.isLast,
    required this.timeLabel,
  });

  final _TimelineStep step;
  final bool isLast;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerColor = step.isDestination
        ? theme.colorScheme.primary
        : step.isOrigin
        ? theme.colorScheme.onSurface
        : theme.colorScheme.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                if (step.isAlight)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: AppColors.lime,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Symbols.arrow_downward_rounded,
                      size: 18,
                      color: AppColors.ink,
                    ),
                  )
                else if (step.transitLabel != null)
                  LineChip(
                    label: step.transitLabel!,
                    backgroundColor: theme.colorScheme.primary,
                    compact: true,
                  )
                else
                  Icon(step.icon, size: 20, color: markerColor),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (step.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        step.subtitle!,
                        style: theme.textTheme.bodySmall,
                      ),
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

class _SummaryFact extends StatelessWidget {
  const _SummaryFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

int _walkingMinutes(TripPlan plan) {
  var seconds = 0;
  for (final leg in plan.legs) {
    if (leg.kind == TripLegKind.walking) {
      seconds += leg.arrivalTime.difference(leg.departureTime).inSeconds;
    }
  }
  return (seconds / 60).ceil();
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
