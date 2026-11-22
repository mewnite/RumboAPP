import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/rumbo_components.dart';
import '../../../core/widgets/line_chip.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../stops_and_lines/data/transit_arrivals_source.dart';
import '../../stops_and_lines/data/stm_linevariant_catalog.dart';
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
        if (firstTransitLegIndex >= 0)
          _TripLegEtaCard(
            plan: plan,
            legIndex: firstTransitLegIndex,
            showLiveEta: true,
            compact: true,
            livePositions: livePositions,
            shapes: tripPlanShapes,
          ),
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
          if (plan.legs[index].kind == TripLegKind.transit &&
              index != firstTransitLegIndex)
            _TripLegEtaCard(
              plan: plan,
              legIndex: index,
              showLiveEta: false,
              compact: false,
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

class _TripLegEtaCard extends ConsumerStatefulWidget {
  const _TripLegEtaCard({
    required this.plan,
    required this.legIndex,
    required this.showLiveEta,
    required this.compact,
    required this.livePositions,
    required this.shapes,
  });

  final TripPlan plan;
  final int legIndex;
  final bool showLiveEta;
  final bool compact;
  final List<BusPosition> livePositions;
  final Map<String, Shape> shapes;

  @override
  ConsumerState<_TripLegEtaCard> createState() => _TripLegEtaCardState();
}

class _TripLegEtaCardState extends ConsumerState<_TripLegEtaCard> {
  static const _pollInterval = Duration(seconds: 30);

  Timer? _pollTimer;
  OfficialUpcomingBusArrivalsSource? _officialSource;
  List<OfficialBusArrival>? _officialArrivals;
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _startOfficialPolling();
  }

  @override
  void didUpdateWidget(covariant _TripLegEtaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLeg = oldWidget.plan.legs[oldWidget.legIndex];
    final leg = widget.plan.legs[widget.legIndex];
    final queryChanged =
        oldLeg.fromStop?.id != leg.fromStop?.id ||
        oldLeg.route?.shortName != leg.route?.shortName ||
        oldLeg.variant?.externalVariantId != leg.variant?.externalVariantId;
    if (oldWidget.showLiveEta != widget.showLiveEta || queryChanged) {
      _stopOfficialPolling();
      _officialArrivals = null;
      _startOfficialPolling();
    }
  }

  @override
  void dispose() {
    _stopOfficialPolling();
    super.dispose();
  }

  void _startOfficialPolling() {
    final leg = widget.plan.legs[widget.legIndex];
    final route = leg.route;
    if (!widget.showLiveEta ||
        leg.fromStop == null ||
        route == null ||
        _externalVariantId(leg.variant) == null) {
      return;
    }
    _officialSource = ref.read(
      officialUpcomingBusArrivalsSourceFactoryProvider,
    )();
    unawaited(_refreshOfficialArrivals());
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_refreshOfficialArrivals());
    });
  }

  void _stopOfficialPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _requestGeneration++;
    _requestInFlight = false;
    _officialSource?.close();
    _officialSource = null;
  }

  Future<void> _refreshOfficialArrivals() async {
    final source = _officialSource;
    if (source == null || _requestInFlight) return;
    final leg = widget.plan.legs[widget.legIndex];
    final stop = leg.fromStop;
    final route = leg.route;
    if (stop == null || route == null) return;

    _requestInFlight = true;
    final requestGeneration = ++_requestGeneration;
    try {
      final arrivals = await source.upcomingForStop(
        stopId: stop.id,
        lines: {route.shortName.isEmpty ? route.id : route.shortName},
        amountPerLine: 5,
      );
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() => _officialArrivals = arrivals);
      }
    } on Exception catch (error) {
      debugPrint('[trip_eta] official arrivals failed: $error');
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() => _officialArrivals = null);
      }
    } finally {
      if (requestGeneration == _requestGeneration) {
        _requestInFlight = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final leg = widget.plan.legs[widget.legIndex];
    final stop = leg.fromStop;
    final route = leg.route;
    if (stop == null || route == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final line = route.shortName.isEmpty ? route.id : route.shortName;
    final matchingOfficial = _matchingOfficialArrivals(leg, line);
    final estimate = estimateTripLegEta(
      plan: widget.plan,
      legIndex: widget.legIndex,
      livePositions: widget.showLiveEta ? widget.livePositions : const [],
      shapes: widget.shapes,
      now: DateTime.now(),
      considerMissedBoarding: widget.showLiveEta,
      officialEtaSeconds: matchingOfficial.isEmpty
          ? null
          : matchingOfficial.first.etaSeconds,
      nextOfficialEtaSeconds: matchingOfficial.length < 2
          ? null
          : matchingOfficial[1].etaSeconds,
    );
    final theme = Theme.of(context);
    final nextDepartures =
        estimate.missedBoarding && estimate.nextOfficialMinutes == null
        ? ref.watch(_scheduledDeparturesProvider(stop.id))
        : null;

    return Card(
      key: widget.compact ? const ValueKey('trip-first-bus-eta') : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.tripEtaBoardingStop(line, stop.name),
              style: theme.textTheme.titleSmall,
              maxLines: widget.compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: widget.compact ? 2 : 4),
            Text(
              !widget.showLiveEta
                  ? l10n.tripEtaFutureScheduledTime(_clock(leg.departureTime))
                  : estimate.source == TripEtaSource.official
                  ? l10n.tripEtaOfficialMinutes(estimate.minMinutes)
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
              if (estimate.nextOfficialMinutes != null)
                Text(l10n.tripEtaNextOfficial(estimate.nextOfficialMinutes!))
              else
                nextDepartures!.when(
                  data: (departures) {
                    final next = _nextScheduledDeparture(
                      departures,
                      leg,
                      DateTime.now(),
                    );
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

  List<OfficialBusArrival> _matchingOfficialArrivals(TripLeg leg, String line) {
    final variantId = _externalVariantId(leg.variant);
    if (variantId == null) return const [];
    final arrivals =
        (_officialArrivals ?? const <OfficialBusArrival>[])
            .where(
              (arrival) =>
                  normalizeTransitLabel(arrival.line) ==
                      normalizeTransitLabel(line) &&
                  arrival.lineVariantId == variantId,
            )
            .toList()
          ..sort((a, b) => a.etaSeconds.compareTo(b.etaSeconds));
    return arrivals;
  }

  UpcomingDeparture? _nextScheduledDeparture(
    List<UpcomingDeparture> departures,
    TripLeg leg,
    DateTime now,
  ) {
    final variantId = leg.variant?.id;
    final matching = departures.where(
      (departure) =>
          departure.trip.routeId == leg.route?.id &&
          (variantId == null || departure.trip.variantId == variantId) &&
          departure.departure.isAfter(leg.departureTime) &&
          departure.departure.isAfter(now),
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
    required this.usesFallbackSpeed,
    required this.walkingMinutes,
    required this.missedBoarding,
    required this.source,
    this.nextOfficialMinutes,
  });

  final int minMinutes;
  final int maxMinutes;
  final TripEtaSource source;
  final bool usesFallbackSpeed;
  final int walkingMinutes;
  final bool missedBoarding;
  final int? nextOfficialMinutes;

  bool get fromGps => source == TripEtaSource.gps;
}

enum TripEtaSource { official, gps, scheduled }

TripLegEtaEstimate estimateTripLegEta({
  required TripPlan plan,
  required int legIndex,
  required List<BusPosition> livePositions,
  required Map<String, Shape> shapes,
  required DateTime now,
  bool considerMissedBoarding = true,
  int? officialEtaSeconds,
  int? nextOfficialEtaSeconds,
}) {
  final leg = plan.legs[legIndex];
  final stop = leg.fromStop;
  final variant = leg.variant;
  final shape = variant == null ? null : shapes[variant.id] ?? leg.shape;
  final externalVariantId = _externalVariantId(variant);
  ({int min, int max, bool fallback})? liveEstimate;
  if (stop != null && externalVariantId != null && shape != null) {
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
  final officialMinutes = officialEtaSeconds == null
      ? null
      : math.max(0, (officialEtaSeconds / 60).ceil()).toInt();
  final nextOfficialMinutes = nextOfficialEtaSeconds == null
      ? null
      : math.max(0, (nextOfficialEtaSeconds / 60).ceil()).toInt();
  final scheduledMinutes = math
      .max(0, (leg.departureTime.difference(now).inSeconds / 60).ceil())
      .toInt();
  final source = officialMinutes != null
      ? TripEtaSource.official
      : liveEstimate != null
      ? TripEtaSource.gps
      : TripEtaSource.scheduled;
  final minMinutes = officialMinutes ?? liveEstimate?.min ?? scheduledMinutes;
  final maxMinutes = officialMinutes ?? liveEstimate?.max ?? scheduledMinutes;
  final missedBoarding =
      considerMissedBoarding &&
      hasWalkingLeg &&
      walkingIsReal &&
      !leg.departureTime.isBefore(now.subtract(const Duration(minutes: 1))) &&
      minMinutes <= walkingMinutes + 1;
  return TripLegEtaEstimate(
    minMinutes: minMinutes,
    maxMinutes: maxMinutes,
    source: source,
    usesFallbackSpeed: liveEstimate?.fallback ?? false,
    walkingMinutes: walkingMinutes,
    missedBoarding: missedBoarding,
    nextOfficialMinutes: nextOfficialMinutes,
  );
}

int? _externalVariantId(RouteVariant? variant) =>
    variant?.externalVariantId ?? int.tryParse(variant?.shapeId ?? '');

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
