import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/debug/performance_measurement.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../../stops_and_lines/domain/transit_repository.dart';
import 'plan_search_isolate.dart';
import 'planner_config.dart';
import 'walk_graph.dart';
import 'walk_graph_worker.dart';

class TripEndpoint {
  const TripEndpoint({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.stop,
    this.route,
    this.isApproximate = false,
  });

  factory TripEndpoint.fromStop(Stop stop) => TripEndpoint(
    name: stop.name,
    latitude: stop.latitude,
    longitude: stop.longitude,
    stop: stop,
  );

  factory TripEndpoint.fromRoute(
    Route route, {
    double latitude = -34.9058,
    double longitude = -56.1991,
  }) => TripEndpoint(
    name: route.shortName.isNotEmpty ? 'Línea ${route.shortName}' : route.id,
    latitude: latitude,
    longitude: longitude,
    route: route,
  );

  final String name;
  final double latitude;
  final double longitude;
  final Stop? stop;
  final Route? route;
  final bool isApproximate;
}

enum TripTimingMode { departNow, departAt, arriveBy }

class TripTiming {
  const TripTiming.departNow()
    : mode = TripTimingMode.departNow,
      dateTime = null;

  const TripTiming.departAt(DateTime time)
    : mode = TripTimingMode.departAt,
      dateTime = time;

  const TripTiming.arriveBy(DateTime time)
    : mode = TripTimingMode.arriveBy,
      dateTime = time;

  final TripTimingMode mode;
  final DateTime? dateTime;

  bool isPast(DateTime now) => dateTime?.isBefore(now) ?? false;
}

class TripRequest {
  const TripRequest({
    required this.originLatitude,
    required this.originLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.timing,
    this.config = const PlannerConfig(),
  });

  final double originLatitude;
  final double originLongitude;
  final double destinationLatitude;
  final double destinationLongitude;
  final TripTiming timing;
  final PlannerConfig config;

  DateTime? get departureTime => timing.dateTime;

  TripRequest copyWith({TripTiming? timing, PlannerConfig? config}) =>
      TripRequest(
        originLatitude: originLatitude,
        originLongitude: originLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
        timing: timing ?? this.timing,
        config: config ?? this.config,
      );
}

enum TripPlanSort { fastest, leastWalking, fewestTransfers }

/// Ordena itinerarios sin volver a ejecutar la búsqueda.
///
/// Cada modo usa su métrica principal y desempata por hora de llegada.
List<TripPlan> sortTripPlans(Iterable<TripPlan> plans, TripPlanSort sort) {
  final sorted = plans.toList(growable: false);
  sorted.sort((a, b) {
    final primary = switch (sort) {
      TripPlanSort.fastest => 0,
      TripPlanSort.leastWalking => a.totalWalkingMeters.compareTo(
        b.totalWalkingMeters,
      ),
      TripPlanSort.fewestTransfers => a.transferCount.compareTo(
        b.transferCount,
      ),
    };
    if (primary != 0) return primary;
    final arrival = a.arrivalTime.compareTo(b.arrivalTime);
    if (arrival != 0) return arrival;
    final transfers = a.transferCount.compareTo(b.transferCount);
    if (transfers != 0) return transfers;
    return a.totalWalkingMeters.compareTo(b.totalWalkingMeters);
  });
  return sorted;
}

enum TripLegKind { walking, waiting, transit }

enum TripTimeAccuracy { scheduled }

class TripLeg {
  const TripLeg({
    required this.kind,
    required this.departureTime,
    required this.arrivalTime,
    this.distanceMeters = 0,
    this.fromStop,
    this.toStop,
    this.fromLatitude,
    this.fromLongitude,
    this.toLatitude,
    this.toLongitude,
    this.route,
    this.variant,
    this.shape,
    this.headsign = '',
    this.approximate = false,
    this.gapMeters = 0,
  });

  final TripLegKind kind;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final double distanceMeters;
  final Stop? fromStop;
  final Stop? toStop;
  final double? fromLatitude;
  final double? fromLongitude;
  final double? toLatitude;
  final double? toLongitude;
  final Route? route;
  final RouteVariant? variant;
  final Shape? shape;
  final String headsign;

  /// true si la geometría del tramo es estimada (sin grafo peatonal) — no
  /// representa una ruta real.
  final bool approximate;

  /// Distancia del punto real del usuario al punto proyectado donde empieza
  /// el camino real peatonal — 0 si no hay gap punteado. Usado para dibujar
  /// el segmento punteado user→proyectado.
  final double gapMeters;

  /// Devuelve una copia del tramo con la geometría (y el estado de
  /// aproximado) reemplazados — usado al recalcular tramos peatonales.
  TripLeg copyWithShape({Shape? shape, bool? approximate, double? gapMeters}) =>
      TripLeg(
        kind: kind,
        departureTime: departureTime,
        arrivalTime: arrivalTime,
        distanceMeters: distanceMeters,
        fromStop: fromStop,
        toStop: toStop,
        fromLatitude: fromLatitude,
        fromLongitude: fromLongitude,
        toLatitude: toLatitude,
        toLongitude: toLongitude,
        route: route,
        variant: variant,
        shape: shape ?? this.shape,
        headsign: headsign,
        approximate: approximate ?? this.approximate,
        gapMeters: gapMeters ?? this.gapMeters,
      );
}

class TripPlan {
  const TripPlan({
    required this.requestedDeparture,
    required this.arrivalTime,
    required this.legs,
    required this.totalWalkingMeters,
    required this.transferCount,
    this.timeAccuracy = TripTimeAccuracy.scheduled,
  });

  final DateTime requestedDeparture;
  final DateTime arrivalTime;
  final List<TripLeg> legs;
  final double totalWalkingMeters;
  final int transferCount;
  final TripTimeAccuracy timeAccuracy;

  Duration get duration => arrivalTime.difference(requestedDeparture);
}

class TransitTripPlanner {
  TransitTripPlanner(this._repository, {this.now, this.walkGraphWorker});

  final TransitRepository _repository;
  final DateTime Function()? now;

  WalkGraphWorker? walkGraphWorker;
  PlanSearchCancellation? _activeCancellation;

  /// Recalcula los tramos peatonales enviando el plan al worker residente.
  Future<TripPlan> refreshWalkingSegments(TripPlan plan) async {
    final worker = walkGraphWorker;
    if (worker != null) return worker.refreshWalkingSegments(plan);
    return refreshWalkingSegmentsSync(plan);
  }

  void cancelPendingSearch() {
    _activeCancellation?.cancel();
    _activeCancellation = null;
  }

  Future<List<TripPlan>> plan(TripRequest request) async {
    cancelPendingSearch();
    final cancellation = PlanSearchCancellation();
    _activeCancellation = cancellation;
    final measurement = PerformanceMeasurement.start('trip.plan');
    _validateRequest(request);
    final current = now?.call() ?? DateTime.now();
    if (request.timing.isPast(current)) {
      measurement.finish(details: 'plans=0');
      _activeCancellation = null;
      return const [];
    }
    final config = request.config;
    final scheduleWindowStart = switch (request.timing.mode) {
      TripTimingMode.departNow => current,
      TripTimingMode.departAt => request.timing.dateTime!,
      TripTimingMode.arriveBy => request.timing.dateTime!.subtract(
        const Duration(minutes: _arrivalSearchWindowMinutes),
      ),
    };
    final scheduleWindowEnd = switch (request.timing.mode) {
      TripTimingMode.arriveBy => request.timing.dateTime!,
      TripTimingMode.departNow || TripTimingMode.departAt =>
        scheduleWindowStart.add(config.maximumWait + const Duration(hours: 3)),
    };
    final nearbyCache = <(double, double, double), Future<List<Stop>>>{};
    Future<List<Stop>> nearby(double latitude, double longitude) {
      final key = (latitude, longitude, config.maximumWalkingMeters);
      return nearbyCache.putIfAbsent(
        key,
        () => _repository.nearbyStops(
          latitude,
          longitude,
          config.maximumWalkingMeters,
        ),
      );
    }

    final sqliteWatch = Stopwatch()..start();
    final nearbyEndpoints = await Future.wait([
      nearby(request.originLatitude, request.originLongitude),
      nearby(request.destinationLatitude, request.destinationLongitude),
    ]);
    sqliteWatch.stop();
    debugPrint(
      '[performance] trip.stage_sqlite_stops=${sqliteWatch.elapsedMilliseconds}ms '
      'origins=${nearbyEndpoints[0].length} destinations=${nearbyEndpoints[1].length}',
    );
    if (cancellation.isCancelled) {
      measurement.finish(details: 'cancelled=true');
      return const [];
    }
    final origins = nearbyEndpoints[0]
        .take(_maximumEndpointStopCandidates)
        .toList(growable: false);
    final destinations = nearbyEndpoints[1]
        .take(_maximumEndpointStopCandidates)
        .toList(growable: false);

    var data = const TransitScheduleData();
    if (origins.isNotEmpty) {
      // A viable first leg must serve an origin stop; a viable final leg must
      // serve a destination stop. Each schedule query returns the full trip
      // pattern, so nearby transfer points are present in these two route
      // sets without expanding schedules across every stop in the area.
      final relevantStopIds = <String>{
        ...origins.map((stop) => stop.id),
        ...destinations.map((stop) => stop.id),
      };
      final scheduleWatch = Stopwatch()..start();
      data = await _repository.scheduleForStops(
        relevantStopIds,
        windowStart: scheduleWindowStart,
        windowEnd: scheduleWindowEnd,
      );
      scheduleWatch.stop();
      debugPrint(
        '[performance] trip.stage_schedule_stops='
        '${scheduleWatch.elapsedMilliseconds}ms',
      );
    }
    if (cancellation.isCancelled) {
      measurement.finish(details: 'cancelled=true');
      return const [];
    }

    final worker = walkGraphWorker;
    final payloadWatch = Stopwatch()..start();
    final payload = PlanSearchPayload(
      request: request,
      data: data,
      originStopIds: origins.map((stop) => stop.id).toSet(),
      destinationStopIds: destinations.map((stop) => stop.id).toSet(),
      now: current,
    );
    payloadWatch.stop();
    debugPrint(
      '[performance] trip.stage_payload=${payloadWatch.elapsedMilliseconds}ms',
    );
    final sendWatch = Stopwatch()..start();
    final plans = worker == null
        ? await runPlanSearch(payload, cancellation: cancellation)
        : await worker.searchPlans(payload, cancellation: cancellation);
    sendWatch.stop();
    debugPrint(
      '[performance] trip.stage_search=${sendWatch.elapsedMilliseconds}ms '
      'plans=${plans.length}',
    );
    final armWatch = Stopwatch()..start();
    measurement.finish(
      details: cancellation.isCancelled
          ? 'cancelled=true'
          : 'plans=${plans.length}',
    );
    armWatch.stop();
    debugPrint(
      '[performance] trip.stage_armado=${armWatch.elapsedMilliseconds}ms',
    );
    if (identical(_activeCancellation, cancellation)) {
      _activeCancellation = null;
    }
    return plans;
  }
}

class PlanSearchPayload {
  const PlanSearchPayload({
    required this.request,
    required this.data,
    required this.originStopIds,
    required this.destinationStopIds,
    required this.now,
  });

  final TripRequest request;
  final TransitScheduleData data;
  final Set<String> originStopIds;
  final Set<String> destinationStopIds;
  final DateTime now;
}

/// Búsqueda pura y sincrónica. También se usa como entrada del isolate.
List<TripPlan> searchPlansSync(
  PlanSearchPayload payload, {
  WalkGraph? walkGraph,
}) {
  return TransitRouteSearch(walkGraph: walkGraph).findPlans(
    request: payload.request,
    data: payload.data,
    originStopIds: payload.originStopIds,
    destinationStopIds: payload.destinationStopIds,
    now: payload.now,
  );
}

TripPlan refreshWalkingSegmentsSync(TripPlan plan, {WalkGraph? walkGraph}) {
  final search = TransitRouteSearch(walkGraph: walkGraph);
  var changed = false;
  final legs = <TripLeg>[];
  for (final leg in plan.legs) {
    final refreshed = search.refreshWalkingLeg(leg);
    if (leg.kind == TripLegKind.walking &&
        !identical(refreshed, leg) &&
        !_sameWalkingShape(leg, refreshed)) {
      changed = true;
    }
    legs.add(refreshed);
  }
  if (!changed) return plan;
  return TripPlan(
    requestedDeparture: plan.requestedDeparture,
    arrivalTime: legs.isEmpty ? plan.arrivalTime : legs.last.arrivalTime,
    legs: legs,
    totalWalkingMeters: legs
        .where((leg) => leg.kind == TripLegKind.walking)
        .fold<double>(0, (total, leg) => total + leg.distanceMeters),
    transferCount: plan.transferCount,
    timeAccuracy: plan.timeAccuracy,
  );
}

bool _sameWalkingShape(TripLeg a, TripLeg b) {
  final pointsA = a.shape?.points;
  final pointsB = b.shape?.points;
  if (a.approximate != b.approximate ||
      a.gapMeters != b.gapMeters ||
      a.distanceMeters != b.distanceMeters ||
      a.arrivalTime != b.arrivalTime) {
    return false;
  }
  if (pointsA == null || pointsB == null) return identical(pointsA, pointsB);
  if (pointsA.length != pointsB.length) return false;
  for (var i = 0; i < pointsA.length; i++) {
    if (pointsA[i].latitude != pointsB[i].latitude ||
        pointsA[i].longitude != pointsB[i].longitude) {
      return false;
    }
  }
  return true;
}

const _arrivalSearchStepMinutes = 10;
const _arrivalSearchWindowMinutes = 180;
const _maximumEndpointStopCandidates = 15;
const _maximumRaptorLabelsPerStop = 4;

class _TransitSearchMetrics {
  int originDestinationPairs = 0;
  int patternsTraversed = 0;
  int tripsTraversed = 0;
  int stopTimesRead = 0;
  int candidatesGenerated = 0;
  int transfersEvaluated = 0;
  int walkingCalculations = 0;
  int walkingEstimates = 0;
  int walkingGraphSearches = 0;
  int walkingCacheHits = 0;
}

class TransitRouteSearch {
  const TransitRouteSearch({this.walkGraph});

  /// Red peatonal real para los tramos peatonales (null = sin caminatas).
  final WalkGraph? walkGraph;

  List<TripPlan> findPlans({
    required TripRequest request,
    required TransitScheduleData data,
    required Set<String> originStopIds,
    required Set<String> destinationStopIds,
    DateTime? now,
  }) {
    _validateRequest(request);
    final clock = now ?? DateTime.now();
    if (request.timing.isPast(clock)) return const [];

    final transitWatch = Stopwatch()..start();
    final metrics = _TransitSearchMetrics();
    final walkingOnly = _walkingOnlyPlan(request, clock, metrics: metrics);
    final transitPlans = _findTransitPlans(
      request: request,
      data: data,
      originStopIds: originStopIds,
      destinationStopIds: destinationStopIds,
      clock: clock,
      metrics: metrics,
    );
    final estimatedFinalists = _finalizePlans([
      ?walkingOnly,
      ...transitPlans,
    ], request);
    final finalizedPlans = _finalizePlans(
      _calculateFinalWalking(estimatedFinalists, request, metrics),
      request,
    );
    transitWatch.stop();
    debugPrint(
      '[performance] trip.stage_transit_search='
      '${transitWatch.elapsedMilliseconds}ms originStops=${originStopIds.length} '
      'destinationStops=${destinationStopIds.length} plans=${transitPlans.length}',
    );
    debugPrint(
      '[performance] trip.search_counts '
      'origin_destination_pairs=${originStopIds.length * destinationStopIds.length} '
      'patterns_traversed=${metrics.patternsTraversed} '
      'trips_traversed=${metrics.tripsTraversed} '
      'stop_times_read=${metrics.stopTimesRead} '
      'candidates_generated=${metrics.candidatesGenerated} '
      'candidates_returned=${finalizedPlans.length} '
      'transfers_evaluated=${metrics.transfersEvaluated} '
      'walks_estimated=${metrics.walkingEstimates} '
      'walks_calculated=${metrics.walkingCalculations} '
      'walk_graph_searches=${metrics.walkingGraphSearches} '
      'walk_cache_hits=${metrics.walkingCacheHits}',
    );
    return finalizedPlans;
  }

  List<TripPlan> _calculateFinalWalking(
    List<TripPlan> plans,
    TripRequest request,
    _TransitSearchMetrics metrics,
  ) {
    final geometryCache =
        <(double, double, double, double), _WalkingGeometry>{};
    final finalized = <TripPlan>[];
    for (final plan in plans) {
      if (!plan.legs.any((leg) => leg.kind == TripLegKind.transit)) {
        finalized.add(plan);
        continue;
      }

      final legs = <TripLeg>[];
      var walkingMeters = 0.0;
      DateTime? previousTransitArrival;
      DateTime? pendingWalkArrival;
      var valid = true;
      for (var index = 0; index < plan.legs.length; index++) {
        final leg = plan.legs[index];
        if (leg.kind == TripLegKind.walking) {
          final fromLatitude = leg.fromLatitude;
          final fromLongitude = leg.fromLongitude;
          final toLatitude = leg.toLatitude;
          final toLongitude = leg.toLongitude;
          if (fromLatitude == null ||
              fromLongitude == null ||
              toLatitude == null ||
              toLongitude == null) {
            legs.add(leg);
            walkingMeters += leg.distanceMeters;
            pendingWalkArrival = leg.arrivalTime;
            continue;
          }
          final walk = _walkingLeg(
            fromLatitude,
            fromLongitude,
            leg.departureTime,
            request.config,
            fromStop: leg.fromStop,
            toStop: leg.toStop,
            toLatitude: toLatitude,
            toLongitude: toLongitude,
            metrics: metrics,
            geometryCache: geometryCache,
          );
          legs.add(walk.toLeg());
          walkingMeters += walk.distanceMeters;
          pendingWalkArrival = walk.arrivalTime;
          continue;
        }

        if (leg.kind == TripLegKind.waiting) {
          var readyTime =
              previousTransitArrival?.add(request.config.minimumTransferTime) ??
              plan.requestedDeparture;
          if (pendingWalkArrival != null &&
              pendingWalkArrival.isAfter(readyTime)) {
            readyTime = pendingWalkArrival;
          }
          if (readyTime.isAfter(leg.arrivalTime)) {
            valid = false;
            break;
          }
          legs.add(_copyLegWithDeparture(leg, readyTime));
          pendingWalkArrival = null;
          continue;
        }

        legs.add(leg);
        previousTransitArrival = leg.arrivalTime;
        pendingWalkArrival = null;
      }
      if (!valid || walkingMeters > request.config.maximumWalkingMeters) {
        continue;
      }
      finalized.add(
        TripPlan(
          requestedDeparture: plan.requestedDeparture,
          arrivalTime: legs.isEmpty ? plan.arrivalTime : legs.last.arrivalTime,
          legs: legs,
          totalWalkingMeters: walkingMeters,
          transferCount: plan.transferCount,
          timeAccuracy: plan.timeAccuracy,
        ),
      );
    }
    return finalized;
  }

  List<TripPlan> _findTransitPlans({
    required TripRequest request,
    required TransitScheduleData data,
    required Set<String> originStopIds,
    required Set<String> destinationStopIds,
    required DateTime clock,
    required _TransitSearchMetrics metrics,
  }) {
    if (originStopIds.isEmpty || destinationStopIds.isEmpty) return const [];
    final indexCache = <DateTime, _ScheduleIndex>{};
    switch (request.timing.mode) {
      case TripTimingMode.departNow:
        final departure = clock;
        return _findForward(
          request: request.copyWith(timing: TripTiming.departAt(departure)),
          data: data,
          originStopIds: originStopIds,
          destinationStopIds: destinationStopIds,
          indexCache: indexCache,
          indexWindowStart: departure,
          indexWindowEnd: departure.add(const Duration(hours: 3)),
          metrics: metrics,
        );
      case TripTimingMode.departAt:
        final departure = request.departureTime!;
        return _findForward(
          request: request,
          data: data,
          originStopIds: originStopIds,
          destinationStopIds: destinationStopIds,
          indexCache: indexCache,
          indexWindowStart: departure,
          indexWindowEnd: departure.add(const Duration(hours: 3)),
          metrics: metrics,
        );
      case TripTimingMode.arriveBy:
        final target = request.timing.dateTime!;
        final indexWindowStart = target.subtract(
          const Duration(minutes: _arrivalSearchWindowMinutes),
        );
        final indexWindowEnd = target.add(const Duration(hours: 3));
        for (
          var minutes = _arrivalSearchStepMinutes;
          minutes <= _arrivalSearchWindowMinutes;
          minutes += _arrivalSearchStepMinutes
        ) {
          final candidate = target.subtract(Duration(minutes: minutes));
          final plans =
              _findForward(
                    request: request.copyWith(
                      timing: TripTiming.departAt(candidate),
                    ),
                    data: data,
                    originStopIds: originStopIds,
                    destinationStopIds: destinationStopIds,
                    indexCache: indexCache,
                    indexWindowStart: indexWindowStart,
                    indexWindowEnd: indexWindowEnd,
                    metrics: metrics,
                  )
                  .where((plan) => !plan.arrivalTime.isAfter(target))
                  .toList(growable: false);
          if (plans.isNotEmpty) return plans;
        }
        return const [];
    }
  }

  List<TripPlan> _findForward({
    required TripRequest request,
    required TransitScheduleData data,
    required Set<String> originStopIds,
    required Set<String> destinationStopIds,
    required Map<DateTime, _ScheduleIndex> indexCache,
    required DateTime indexWindowStart,
    required DateTime indexWindowEnd,
    required _TransitSearchMetrics metrics,
  }) {
    final departureTime = request.departureTime;
    if (departureTime == null) return const [];
    final serviceDay = DateTime(
      departureTime.year,
      departureTime.month,
      departureTime.day,
    );
    final indexWatch = Stopwatch()..start();
    final index = indexCache.putIfAbsent(
      serviceDay,
      () => _ScheduleIndex.build(
        data,
        serviceDay,
        windowStart: indexWindowStart,
        windowEnd: indexWindowEnd,
        maximumTransferWalkingMeters:
            request.config.maximumTransferWalkingMeters,
      ),
    );
    indexWatch.stop();
    debugPrint(
      '[performance] trip.schedule_index_ms=${indexWatch.elapsedMilliseconds} '
      'stops=${data.stops.length} trips=${data.trips.length} '
      'stop_times=${data.stopTimes.length}',
    );
    metrics.originDestinationPairs +=
        originStopIds.length * destinationStopIds.length;

    final config = request.config;
    final searchHorizon = departureTime.add(const Duration(hours: 3));
    final seeds = <_RaptorSeed>[];
    for (final originStopId in originStopIds) {
      final boardStop = index.stopsById[originStopId];
      if (boardStop == null) continue;
      final initialWalk = _estimateWalkingLeg(
        request.originLatitude,
        request.originLongitude,
        departureTime,
        config,
        toStop: boardStop,
        toLatitude: boardStop.latitude,
        toLongitude: boardStop.longitude,
        metrics: metrics,
      );
      if (initialWalk.distanceMeters > config.maximumWalkingMeters) continue;
      final readyTime = initialWalk.arrivalTime;
      final maximumDeparture = readyTime.add(config.maximumWait);
      seeds.add(
        _RaptorSeed(
          stopId: originStopId,
          readyTime: readyTime,
          latestDeparture: maximumDeparture.isBefore(searchHorizon)
              ? maximumDeparture
              : searchHorizon,
          initialWalk: initialWalk,
          walkingMeters: initialWalk.distanceMeters,
        ),
      );
    }

    final plans = <TripPlan>[];
    final candidateLimit = config.resultLimit * 2;
    var roundNumber = 0;
    var round = _scanRaptorRound(
      seeds: seeds,
      request: request,
      departureTime: departureTime,
      index: index,
      destinationStopIds: destinationStopIds,
      searchHorizon: searchHorizon,
      bestPlans: plans,
      candidateLimit: candidateLimit,
      roundNumber: roundNumber,
      metrics: metrics,
    );

    for (
      var transferCount = 1;
      transferCount <= config.maximumTransfers;
      transferCount++
    ) {
      if (round.labelsByStop.isEmpty) break;
      final transferSeedWatch = Stopwatch()..start();
      final transferSeeds = _buildTransferSeeds(
        labelsByStop: round.labelsByStop,
        request: request,
        index: index,
        searchHorizon: searchHorizon,
        metrics: metrics,
      );
      transferSeedWatch.stop();
      debugPrint(
        '[performance] trip.transfer_seeds_ms='
        '${transferSeedWatch.elapsedMilliseconds} round=$transferCount '
        'seeds=${transferSeeds.length} labels='
        '${round.labelsByStop.values.fold<int>(0, (sum, labels) => sum + labels.length)}',
      );
      if (transferSeeds.isEmpty) break;
      roundNumber++;
      round = _scanRaptorRound(
        seeds: transferSeeds,
        request: request,
        departureTime: departureTime,
        index: index,
        destinationStopIds: destinationStopIds,
        searchHorizon: searchHorizon,
        bestPlans: plans,
        candidateLimit: candidateLimit,
        roundNumber: roundNumber,
        metrics: metrics,
      );
    }
    return plans;
  }

  _RaptorRoundResult _scanRaptorRound({
    required List<_RaptorSeed> seeds,
    required TripRequest request,
    required DateTime departureTime,
    required _ScheduleIndex index,
    required Set<String> destinationStopIds,
    required DateTime searchHorizon,
    required List<TripPlan> bestPlans,
    required int candidateLimit,
    required int roundNumber,
    required _TransitSearchMetrics metrics,
  }) {
    final roundWatch = Stopwatch()..start();
    final config = request.config;
    final seedsByStop = <String, List<_RaptorSeed>>{};
    final patternsToScan = <String, _TransitPattern>{};
    for (final seed in seeds) {
      seedsByStop.putIfAbsent(seed.stopId, () => []).add(seed);
      for (final boarding in index.patternsByStop[seed.stopId] ?? const []) {
        patternsToScan[boarding.pattern.id] = boarding.pattern;
      }
    }

    final labelsByStop = <String, List<_RaptorLabel>>{};
    for (final pattern in patternsToScan.values) {
      metrics.patternsTraversed++;
      for (
        var boardIndex = 0;
        boardIndex < pattern.stopIds.length - 1;
        boardIndex++
      ) {
        final boardingSeeds = seedsByStop[pattern.stopIds[boardIndex]];
        if (boardingSeeds == null) continue;
        for (final seed in boardingSeeds) {
          final excludedTripIds = seed.prefix == null
              ? const <String>{}
              : {seed.prefix!.rides.last.instance.trip.id};
          final connection = pattern.nextDeparture(
            boardIndex,
            seed.readyTime,
            seed.latestDeparture.isBefore(searchHorizon)
                ? seed.latestDeparture
                : searchHorizon,
            excludedTripIds,
            metrics,
          );
          if (connection == null) continue;
          metrics.tripsTraversed++;
          final instance = connection.instance;
          final searchHorizonMilliseconds =
              searchHorizon.millisecondsSinceEpoch;
          for (
            var alightIndex = boardIndex + 1;
            alightIndex < instance.times.length;
            alightIndex++
          ) {
            metrics.stopTimesRead++;
            final arrivalMilliseconds = instance.arrivalMilliseconds(
              alightIndex,
            );
            if (arrivalMilliseconds > searchHorizonMilliseconds) break;
            if (bestPlans.length >= candidateLimit &&
                candidateLimit > 0 &&
                instance.isChronological &&
                arrivalMilliseconds >
                    bestPlans.last.arrivalTime.millisecondsSinceEpoch) {
              break;
            }
            final alightStopId = instance.times[alightIndex].stopId;
            final isDestination = destinationStopIds.contains(alightStopId);
            final needsLabel =
                seed.walkingMeters <= config.maximumWalkingMeters &&
                _canAddRaptorLabel(
                  labelsByStop[alightStopId],
                  arrivalMilliseconds,
                  seed.walkingMeters,
                );
            if (!needsLabel && !isDestination) continue;
            final alightStop = index.stopsById[alightStopId];
            if (alightStop == null) continue;
            final prefix = seed.prefix;
            final arrival = instance.arrivalTime(alightIndex);
            final candidate = _RaptorLabel(
              arrivalTime: arrival,
              initialWalk: seed.initialWalk,
              rides: [
                if (prefix != null) ...prefix.rides,
                _RaptorRide(
                  instance: instance,
                  boardIndex: boardIndex,
                  alightIndex: alightIndex,
                ),
              ],
              transferWalks: [
                if (prefix != null) ...prefix.transferWalks,
                if (prefix != null) seed.transferWalk,
              ],
              walkingMeters: seed.walkingMeters,
            );
            if (needsLabel) {
              _addRaptorLabel(labelsByStop, alightStopId, candidate);
            }

            if (!isDestination) continue;
            final finalWalk = _estimateWalkingLeg(
              alightStop.latitude,
              alightStop.longitude,
              arrival,
              config,
              fromStop: alightStop,
              toLatitude: request.destinationLatitude,
              toLongitude: request.destinationLongitude,
              metrics: metrics,
            );
            final totalWalking =
                candidate.walkingMeters + finalWalk.distanceMeters;
            if (totalWalking > config.maximumWalkingMeters) continue;
            metrics.candidatesGenerated++;
            final planArrival = finalWalk.arrivalTime;
            if (!_shouldKeepRaptorPlan(
              bestPlans,
              planArrival,
              candidate.rides.length - 1,
              totalWalking,
              candidateLimit,
            )) {
              continue;
            }
            bestPlans.add(
              _buildRaptorPlan(
                candidate,
                finalWalk,
                departureTime,
                totalWalking,
                index.stopsById,
              ),
            );
            bestPlans.sort(_compareFastestPlans);
            if (bestPlans.length > candidateLimit) bestPlans.removeLast();
          }
        }
      }
    }
    roundWatch.stop();
    debugPrint(
      '[performance] trip.raptor_round_ms=${roundWatch.elapsedMilliseconds} '
      'round=$roundNumber seeds=${seeds.length} '
      'patterns=${patternsToScan.length} '
      'labels=${labelsByStop.values.fold<int>(0, (sum, labels) => sum + labels.length)} '
      'best_plans=${bestPlans.length}',
    );
    return _RaptorRoundResult(labelsByStop);
  }

  List<_RaptorSeed> _buildTransferSeeds({
    required Map<String, List<_RaptorLabel>> labelsByStop,
    required TripRequest request,
    required _ScheduleIndex index,
    required DateTime searchHorizon,
    required _TransitSearchMetrics metrics,
  }) {
    final config = request.config;
    final seedsByKey = <(String, String), _RaptorSeed>{};
    for (final entry in labelsByStop.entries) {
      final fromStop = index.stopsById[entry.key];
      if (fromStop == null) continue;
      final targets = index.transferStopsByStop[fromStop.id] ?? const [];
      for (final label in entry.value) {
        for (final target in targets) {
          metrics.transfersEvaluated++;
          final transferWalk = target.id == fromStop.id
              ? null
              : _estimateWalkingLeg(
                  fromStop.latitude,
                  fromStop.longitude,
                  label.arrivalTime,
                  config,
                  fromStop: fromStop,
                  toStop: target,
                  toLatitude: target.latitude,
                  toLongitude: target.longitude,
                  metrics: metrics,
                );
          final walkingMeters =
              label.walkingMeters + (transferWalk?.distanceMeters ?? 0);
          if (walkingMeters > config.maximumWalkingMeters) continue;
          final readyTime = transferWalk?.arrivalTime ?? label.arrivalTime;
          final minimumDeparture = label.arrivalTime.add(
            config.minimumTransferTime,
          );
          final earliestDeparture = readyTime.isAfter(minimumDeparture)
              ? readyTime
              : minimumDeparture;
          final latestDeparture = label.arrivalTime.add(config.maximumWait);
          final boundedLatest = latestDeparture.isBefore(searchHorizon)
              ? latestDeparture
              : searchHorizon;
          if (earliestDeparture.isAfter(boundedLatest)) continue;
          final key = (target.id, label.rides.last.instance.trip.id);
          final candidate = _RaptorSeed(
            stopId: target.id,
            readyTime: earliestDeparture,
            latestDeparture: boundedLatest,
            initialWalk: label.initialWalk,
            walkingMeters: walkingMeters,
            prefix: label,
            transferWalk: transferWalk,
          );
          final previous = seedsByKey[key];
          if (previous == null ||
              candidate.readyTime.isBefore(previous.readyTime) ||
              (candidate.readyTime.isAtSameMomentAs(previous.readyTime) &&
                  candidate.walkingMeters < previous.walkingMeters)) {
            seedsByKey[key] = candidate;
          }
        }
      }
    }
    return seedsByKey.values.toList(growable: false);
  }

  bool _canAddRaptorLabel(
    List<_RaptorLabel>? labels,
    int arrivalMilliseconds,
    double walkingMeters,
  ) {
    if (labels == null) return true;
    return !labels.any(
      (label) =>
          label.arrivalTime.millisecondsSinceEpoch <= arrivalMilliseconds &&
          label.walkingMeters <= walkingMeters,
    );
  }

  void _addRaptorLabel(
    Map<String, List<_RaptorLabel>> labelsByStop,
    String stopId,
    _RaptorLabel candidate,
  ) {
    final labels = labelsByStop.putIfAbsent(stopId, () => []);
    if (labels.any(
      (label) =>
          !label.arrivalTime.isAfter(candidate.arrivalTime) &&
          label.walkingMeters <= candidate.walkingMeters,
    )) {
      return;
    }
    labels.removeWhere(
      (label) =>
          !candidate.arrivalTime.isAfter(label.arrivalTime) &&
          candidate.walkingMeters <= label.walkingMeters,
    );
    labels.add(candidate);
    labels.sort((first, second) {
      final arrival = first.arrivalTime.compareTo(second.arrivalTime);
      if (arrival != 0) return arrival;
      return first.walkingMeters.compareTo(second.walkingMeters);
    });
    if (labels.length > _maximumRaptorLabelsPerStop) {
      labels.removeRange(_maximumRaptorLabelsPerStop, labels.length);
    }
  }

  TripPlan? _walkingOnlyPlan(
    TripRequest request,
    DateTime clock, {
    required _TransitSearchMetrics metrics,
  }) {
    final config = request.config;
    final straightMeters = _distanceMeters(
      request.originLatitude,
      request.originLongitude,
      request.destinationLatitude,
      request.destinationLongitude,
    );
    if (straightMeters < 1 || straightMeters >= config.maximumWalkingMeters) {
      return null;
    }
    final walk = _walkingLeg(
      request.originLatitude,
      request.originLongitude,
      clock,
      config,
      toLatitude: request.destinationLatitude,
      toLongitude: request.destinationLongitude,
      metrics: metrics,
    );
    final DateTime departure;
    switch (request.timing.mode) {
      case TripTimingMode.departNow:
        departure = clock;
      case TripTimingMode.departAt:
        departure = request.timing.dateTime!;
      case TripTimingMode.arriveBy:
        departure = request.timing.dateTime!.subtract(
          walk.arrivalTime.difference(walk.departureTime),
        );
        if (departure.isBefore(clock)) return null;
    }
    final arrival = departure.add(
      walk.arrivalTime.difference(walk.departureTime),
    );
    return TripPlan(
      requestedDeparture: departure,
      arrivalTime: arrival,
      legs: [walk.copyWithTimes(departure, arrival).toLeg()],
      totalWalkingMeters: walk.distanceMeters,
      transferCount: 0,
    );
  }

  /// Recalcula la geometría, distancia y tiempo de un tramo peatonal con la
  /// red actual ([walkGraph]). El tramo
  /// nunca se omite: con red y snap válido se usa el camino real; si no hay
  /// red ni camino válido, la geometría es la línea recta marcada como
  /// aproximada.
  TripLeg refreshWalkingLeg(TripLeg leg) {
    if (leg.kind != TripLegKind.walking) return leg;
    final fromLatitude = leg.fromLatitude;
    final fromLongitude = leg.fromLongitude;
    final toLatitude = leg.toLatitude;
    final toLongitude = leg.toLongitude;
    if (fromLatitude == null ||
        fromLongitude == null ||
        toLatitude == null ||
        toLongitude == null) {
      return leg;
    }
    final walk = _walkingLeg(
      fromLatitude,
      fromLongitude,
      leg.departureTime,
      PlannerConfig(),
      fromStop: leg.fromStop,
      toStop: leg.toStop,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
    );
    return walk.toLeg();
  }

  _WalkingLeg _estimateWalkingLeg(
    double fromLatitude,
    double fromLongitude,
    DateTime departure,
    PlannerConfig config, {
    Stop? fromStop,
    Stop? toStop,
    required double toLatitude,
    required double toLongitude,
    required _TransitSearchMetrics metrics,
  }) {
    metrics.walkingEstimates++;
    final distanceMeters =
        _distanceMeters(fromLatitude, fromLongitude, toLatitude, toLongitude) *
        config.detourFactor;
    return _WalkingLeg(
      fromStop: fromStop,
      toStop: toStop,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      distanceMeters: distanceMeters,
      departureTime: departure,
      arrivalTime: departure.add(
        Duration(
          seconds: (distanceMeters / config.walkingSpeedMetersPerSecond).ceil(),
        ),
      ),
      approximate: true,
    );
  }

  /// Camino peatonal: con el grafo cargado es la ruta real de la red; sin
  /// grafo o sin camino válido, el tramo mide en línea recta y está marcado
  /// como aproximado (nunca se omite).
  _WalkingLeg _walkingLeg(
    double fromLatitude,
    double fromLongitude,
    DateTime departure,
    PlannerConfig config, {
    Stop? fromStop,
    Stop? toStop,
    required double toLatitude,
    required double toLongitude,
    _TransitSearchMetrics? metrics,
    Map<(double, double, double, double), _WalkingGeometry>? geometryCache,
  }) {
    if (metrics != null) metrics.walkingCalculations++;
    final geometryKey = (fromLatitude, fromLongitude, toLatitude, toLongitude);
    final cachedGeometry = geometryCache?[geometryKey];
    if (cachedGeometry != null) {
      if (metrics != null) metrics.walkingCacheHits++;
      return _walkingLegFromGeometry(
        cachedGeometry,
        fromLatitude,
        fromLongitude,
        departure,
        toLatitude,
        toLongitude,
        fromStop,
        toStop,
        config,
      );
    }

    final graph = walkGraph;
    if (graph != null && metrics != null) metrics.walkingGraphSearches++;
    final path = graph?.shortestPath(
      fromLatitude,
      fromLongitude,
      toLatitude,
      toLongitude,
    );
    final hasPath = path != null && path.points.isNotEmpty;
    final approximate = graph == null || !hasPath;
    // Con grafo: tiempo real sobre la ruta de OSM. Sin camino válido:
    // línea recta con factor de desvío ([PlannerConfig.detourFactor]).
    final distanceMeters =
        path?.lengthMeters ??
        (_distanceMeters(fromLatitude, fromLongitude, toLatitude, toLongitude) *
            config.detourFactor);
    final shape = hasPath
        ? Shape(
            id: "walk:${path.points.first.latitude},${path.points.first.longitude}",
            points: path.points,
          )
        : Shape(
            id: "walk:approx:$fromLatitude,$fromLongitude",
            points: [
              ShapePoint(fromLatitude, fromLongitude, 0),
              ShapePoint(toLatitude, toLongitude, 1),
            ],
          );
    if (approximate && PerformanceMeasurement.enabled) {
      final reason = graph == null
          ? 'sin grafo peatonal'
          : 'snap nulo o sin camino válido';
      developer.log(
        '[caminata] tramo aproximado: desde=${fromStop?.id ?? 'punto'}; '
        'hasta=${toStop?.id ?? 'punto'}; motivo=$reason; '
        'distancia=${distanceMeters.round()}m',
        name: 'Rumbo',
      );
    }
    final geometry = _WalkingGeometry(
      distanceMeters: distanceMeters,
      shape: shape,
      approximate: approximate,
      gapMeters: path?.gapMeters ?? 0,
    );
    if (geometryCache != null) geometryCache[geometryKey] = geometry;
    return _walkingLegFromGeometry(
      geometry,
      fromLatitude,
      fromLongitude,
      departure,
      toLatitude,
      toLongitude,
      fromStop,
      toStop,
      config,
    );
  }

  _WalkingLeg _walkingLegFromGeometry(
    _WalkingGeometry geometry,
    double fromLatitude,
    double fromLongitude,
    DateTime departure,
    double toLatitude,
    double toLongitude,
    Stop? fromStop,
    Stop? toStop,
    PlannerConfig config,
  ) {
    return _WalkingLeg(
      fromStop: fromStop,
      toStop: toStop,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      distanceMeters: geometry.distanceMeters,
      departureTime: departure,
      arrivalTime: departure.add(
        Duration(
          seconds:
              (geometry.distanceMeters / config.walkingSpeedMetersPerSecond)
                  .ceil(),
        ),
      ),
      shape: geometry.shape,
      approximate: geometry.approximate,
      gapMeters: geometry.gapMeters,
    );
  }
}

bool _shouldKeepRaptorPlan(
  List<TripPlan> plans,
  DateTime arrivalTime,
  int transferCount,
  double walkingMeters,
  int resultLimit,
) {
  if (resultLimit <= 0) return false;
  if (plans.length < resultLimit) return true;
  final worst = plans.last;
  final arrival = arrivalTime.compareTo(worst.arrivalTime);
  if (arrival != 0) return arrival < 0;
  final transfers = transferCount.compareTo(worst.transferCount);
  return transfers != 0
      ? transfers < 0
      : walkingMeters < worst.totalWalkingMeters;
}

int _compareFastestPlans(TripPlan first, TripPlan second) {
  final arrival = first.arrivalTime.compareTo(second.arrivalTime);
  if (arrival != 0) return arrival;
  final transfers = first.transferCount.compareTo(second.transferCount);
  if (transfers != 0) return transfers;
  return first.totalWalkingMeters.compareTo(second.totalWalkingMeters);
}

bool _hasServiceDepartureInWindow(
  List<StopTime> times,
  DateTime serviceDay,
  DateTime windowStart,
  DateTime windowEnd,
) {
  final firstSecond = windowStart.difference(serviceDay).inSeconds;
  final lastSecond = windowEnd.difference(serviceDay).inSeconds;
  return times.any(
    (time) =>
        time.departureSeconds >= firstSecond &&
        time.departureSeconds <= lastSecond,
  );
}

TripLeg _copyLegWithDeparture(TripLeg leg, DateTime departureTime) => TripLeg(
  kind: leg.kind,
  departureTime: departureTime,
  arrivalTime: leg.arrivalTime,
  distanceMeters: leg.distanceMeters,
  fromStop: leg.fromStop,
  toStop: leg.toStop,
  fromLatitude: leg.fromLatitude,
  fromLongitude: leg.fromLongitude,
  toLatitude: leg.toLatitude,
  toLongitude: leg.toLongitude,
  route: leg.route,
  variant: leg.variant,
  headsign: leg.headsign,
  shape: leg.shape,
  approximate: leg.approximate,
  gapMeters: leg.gapMeters,
);

List<TripPlan> _finalizePlans(List<TripPlan> plans, TripRequest request) {
  final sorted = sortTripPlans(plans, TripPlanSort.fastest);
  final unique = <String, TripPlan>{};
  for (final plan in sorted) {
    final key = plan.legs
        .where((leg) => leg.kind == TripLegKind.transit)
        .map((leg) => '${leg.route?.id}:${leg.departureTime.toIso8601String()}')
        .join('|');
    unique.putIfAbsent(key, () => plan);
  }
  final kept = <TripPlan>[];
  final minimumWalkingByTransfers = <int, double>{};
  for (final plan in unique.values) {
    final isDominated = Iterable<int>.generate(plan.transferCount + 1)
        .any((transfers) {
          final minimumWalking = minimumWalkingByTransfers[transfers];
          return minimumWalking != null &&
              minimumWalking <= plan.totalWalkingMeters;
        });
    if (isDominated) continue;
    kept.add(plan);
    final minimumWalking =
        minimumWalkingByTransfers[plan.transferCount] ?? double.infinity;
    minimumWalkingByTransfers[plan.transferCount] = math.min(
      minimumWalking,
      plan.totalWalkingMeters,
    );
  }
  return kept.take(request.config.resultLimit).toList(growable: false);
}

class _ScheduleIndex {
  const _ScheduleIndex._({
    required this.stopsById,
    required this.instances,
    required this.patternsByStop,
    required this.stopsByCell,
    required this.cellSizeDegrees,
    required this.transferStopsByStop,
  });

  factory _ScheduleIndex.build(
    TransitScheduleData data,
    DateTime serviceDay, {
    required DateTime windowStart,
    required DateTime windowEnd,
    required double maximumTransferWalkingMeters,
  }) {
    final stageWatch = Stopwatch()..start();
    final stopsById = {for (final stop in data.stops) stop.id: stop};
    final routesById = {for (final route in data.routes) route.id: route};
    final variantsById = {
      for (final variant in data.variants) variant.id: variant,
    };
    final calendarsById = {
      for (final calendar in data.calendars) calendar.serviceId: calendar,
    };
    final serviceDaysById = <String, List<DateTime>>{};
    for (final calendar in data.calendars) {
      final activeDays = <DateTime>[];
      for (final offset in [-1, 0, 1]) {
        final day = serviceDay.add(Duration(days: offset));
        if (calendar.activeOn(day)) activeDays.add(day);
      }
      serviceDaysById[calendar.serviceId] = activeDays;
    }
    stageWatch.stop();
    debugPrint(
      '[performance] trip.index_stage_ms=${stageWatch.elapsedMilliseconds} '
      'stage=calendars stops=${stopsById.length} '
      'calendars=${calendarsById.length}',
    );
    stageWatch
      ..reset()
      ..start();
    final timesByTrip = <String, List<StopTime>>{};
    for (final time in data.stopTimes) {
      timesByTrip.putIfAbsent(time.tripId, () => []).add(time);
    }
    for (final times in timesByTrip.values) {
      times.sort((a, b) => a.sequence.compareTo(b.sequence));
    }
    final chronologicalByTrip = {
      for (final entry in timesByTrip.entries)
        entry.key: _hasChronologicalStopTimes(entry.value),
    };
    stageWatch.stop();
    debugPrint(
      '[performance] trip.index_stage_ms=${stageWatch.elapsedMilliseconds} '
      'stage=trip_stop_times trips=${timesByTrip.length} '
      'rows=${data.stopTimes.length}',
    );
    stageWatch
      ..reset()
      ..start();

    final instances = <_TripInstance>[];
    for (final trip in data.trips) {
      final times = timesByTrip[trip.id];
      final calendar = calendarsById[trip.serviceId];
      final route = routesById[trip.routeId];
      if (times == null ||
          times.length < 2 ||
          calendar == null ||
          route == null) {
        continue;
      }
      for (final day in serviceDaysById[trip.serviceId] ?? const []) {
        if (!_hasServiceDepartureInWindow(times, day, windowStart, windowEnd)) {
          continue;
        }
        instances.add(
          _TripInstance(
            trip: trip,
            route: route,
            variant: variantsById[trip.variantId],
            times: times,
            serviceDay: day,
            isChronological: chronologicalByTrip[trip.id] ?? true,
          ),
        );
      }
    }
    stageWatch.stop();
    debugPrint(
      '[performance] trip.index_stage_ms=${stageWatch.elapsedMilliseconds} '
      'stage=active_instances count=${instances.length}',
    );
    stageWatch
      ..reset()
      ..start();
    final patternBuilders = <String, _TransitPatternBuilder>{};
    for (final instance in instances) {
      final stopIds = instance.times.map((time) => time.stopId).toList();
      final patternId = '${instance.route.id}\u0000${stopIds.join('\u0000')}';
      final builder = patternBuilders.putIfAbsent(
        patternId,
        () => _TransitPatternBuilder(patternId, stopIds),
      );
      for (var index = 0; index < stopIds.length - 1; index++) {
        builder.departuresByStop[index].add(_PatternDeparture(instance, index));
      }
    }
    final patternsByStop = <String, List<_PatternBoarding>>{};
    for (final builder in patternBuilders.values) {
      for (final departures in builder.departuresByStop) {
        departures.sort((first, second) {
          return first.departureMilliseconds.compareTo(
            second.departureMilliseconds,
          );
        });
      }
      final pattern = _TransitPattern(
        id: builder.id,
        stopIds: builder.stopIds,
        departuresByStop: builder.departuresByStop
            .map(List<_PatternDeparture>.unmodifiable)
            .toList(growable: false),
      );
      for (
        var stopIndex = 0;
        stopIndex < pattern.stopIds.length - 1;
        stopIndex++
      ) {
        patternsByStop
            .putIfAbsent(pattern.stopIds[stopIndex], () => [])
            .add(_PatternBoarding(pattern, stopIndex));
      }
    }
    stageWatch.stop();
    debugPrint(
      '[performance] trip.index_stage_ms=${stageWatch.elapsedMilliseconds} '
      'stage=patterns count=${patternBuilders.length}',
    );
    stageWatch
      ..reset()
      ..start();
    final cellSizeMeters = 150.0;
    final cellSizeDegrees = cellSizeMeters / 111320;
    final stopsByCell = <(int, int), List<Stop>>{};
    for (final stop in stopsById.values) {
      final cell = (
        (stop.latitude / cellSizeDegrees).floor(),
        (stop.longitude / cellSizeDegrees).floor(),
      );
      stopsByCell.putIfAbsent(cell, () => <Stop>[]).add(stop);
    }
    final index = _ScheduleIndex._(
      stopsById: stopsById,
      instances: instances,
      patternsByStop: patternsByStop,
      stopsByCell: stopsByCell,
      cellSizeDegrees: cellSizeDegrees,
      transferStopsByStop: const {},
    );
    final transferStopsByStop = <String, List<Stop>>{};
    for (final stop in stopsById.values) {
      final nearby = index
          .nearbyStops(stop, maximumTransferWalkingMeters)
          .where((candidate) => candidate.id != stop.id)
          .toList();
      nearby.sort((first, second) {
        final firstDistance = _distanceMeters(
          stop.latitude,
          stop.longitude,
          first.latitude,
          first.longitude,
        );
        final secondDistance = _distanceMeters(
          stop.latitude,
          stop.longitude,
          second.latitude,
          second.longitude,
        );
        return firstDistance.compareTo(secondDistance);
      });
      transferStopsByStop[stop.id] = [stop, ...nearby.take(6)];
    }
    stageWatch.stop();
    debugPrint(
      '[performance] trip.index_stage_ms=${stageWatch.elapsedMilliseconds} '
      'stage=transfer_neighbors count=${transferStopsByStop.length}',
    );
    return _ScheduleIndex._(
      stopsById: stopsById,
      instances: instances,
      patternsByStop: patternsByStop,
      stopsByCell: stopsByCell,
      cellSizeDegrees: cellSizeDegrees,
      transferStopsByStop: transferStopsByStop,
    );
  }

  final Map<String, Stop> stopsById;
  final List<_TripInstance> instances;
  final Map<String, List<_PatternBoarding>> patternsByStop;
  final Map<(int, int), List<Stop>> stopsByCell;
  final double cellSizeDegrees;
  final Map<String, List<Stop>> transferStopsByStop;

  Iterable<Stop> nearbyStops(Stop center, double radiusMeters) sync* {
    if (radiusMeters < 0) return;
    final latitudeDelta = radiusMeters / 111320;
    final longitudeDelta =
        latitudeDelta / math.cos(_radians(center.latitude)).abs().clamp(.01, 1);
    final minimumLatitudeCell =
        ((center.latitude - latitudeDelta) / cellSizeDegrees).floor();
    final maximumLatitudeCell =
        ((center.latitude + latitudeDelta) / cellSizeDegrees).floor();
    final minimumLongitudeCell =
        ((center.longitude - longitudeDelta) / cellSizeDegrees).floor();
    final maximumLongitudeCell =
        ((center.longitude + longitudeDelta) / cellSizeDegrees).floor();
    for (
      var latitudeCell = minimumLatitudeCell;
      latitudeCell <= maximumLatitudeCell;
      latitudeCell++
    ) {
      for (
        var longitudeCell = minimumLongitudeCell;
        longitudeCell <= maximumLongitudeCell;
        longitudeCell++
      ) {
        for (final stop
            in stopsByCell[(latitudeCell, longitudeCell)] ?? const []) {
          if (_distanceMeters(
                center.latitude,
                center.longitude,
                stop.latitude,
                stop.longitude,
              ) <=
              radiusMeters) {
            yield stop;
          }
        }
      }
    }
  }
}

class _TransitPatternBuilder {
  _TransitPatternBuilder(this.id, this.stopIds)
    : departuresByStop = List.generate(
        stopIds.length,
        (_) => <_PatternDeparture>[],
      );

  final String id;
  final List<String> stopIds;
  final List<List<_PatternDeparture>> departuresByStop;
}

TripLeg _transitLeg(
  _TripInstance instance,
  int boardIndex,
  int alightIndex,
  Map<String, Stop> stopsById,
) => TripLeg(
  kind: TripLegKind.transit,
  departureTime: instance.departureTime(boardIndex),
  arrivalTime: instance.arrivalTime(alightIndex),
  fromStop: stopsById[instance.times[boardIndex].stopId],
  toStop: stopsById[instance.times[alightIndex].stopId],
  route: instance.route,
  variant: instance.variant,
  headsign: instance.trip.headsign,
);

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const radiusMeters = 6371000.0;
  final deltaLat = _radians(lat2 - lat1);
  final deltaLon = _radians(lon2 - lon1);
  final a =
      math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.pow(math.sin(deltaLon / 2), 2);
  return 2 * radiusMeters * math.asin(math.sqrt(a));
}

double _radians(double degrees) => degrees * math.pi / 180;

void _validateRequest(TripRequest request) {
  final coordinates = [
    request.originLatitude,
    request.originLongitude,
    request.destinationLatitude,
    request.destinationLongitude,
  ];
  if (coordinates.any((value) => !value.isFinite) ||
      request.originLatitude < -90 ||
      request.originLatitude > 90 ||
      request.destinationLatitude < -90 ||
      request.destinationLatitude > 90 ||
      request.originLongitude < -180 ||
      request.originLongitude > 180 ||
      request.destinationLongitude < -180 ||
      request.destinationLongitude > 180) {
    throw ArgumentError('Las coordenadas del viaje no son válidas.');
  }
  final config = request.config;
  if (!config.detourFactor.isFinite ||
      config.detourFactor < 1 ||
      !config.walkingSpeedKmh.isFinite ||
      config.walkingSpeedKmh <= 0 ||
      !config.maximumWalkingMeters.isFinite ||
      config.maximumWalkingMeters < 0 ||
      !config.maximumTransferWalkingMeters.isFinite ||
      config.maximumTransferWalkingMeters < 0 ||
      config.minimumTransferTime.isNegative ||
      config.maximumTransfers < 0 ||
      config.maximumTransfers > 2 ||
      config.resultLimit < 0 ||
      config.maximumWait.isNegative) {
    throw ArgumentError('Los parámetros del viaje no son válidos.');
  }
}

class _TripInstance {
  _TripInstance({
    required this.trip,
    required this.route,
    required this.variant,
    required this.times,
    required this.serviceDay,
    required this.isChronological,
  }) : serviceDayMilliseconds = serviceDay.millisecondsSinceEpoch;

  final Trip trip;
  final Route route;
  final RouteVariant? variant;
  final List<StopTime> times;
  final DateTime serviceDay;
  final bool isChronological;
  final int serviceDayMilliseconds;

  int arrivalMilliseconds(int index) =>
      serviceDayMilliseconds +
      times[index].arrivalSeconds * Duration.millisecondsPerSecond;

  int departureMilliseconds(int index) =>
      serviceDayMilliseconds +
      times[index].departureSeconds * Duration.millisecondsPerSecond;

  DateTime arrivalTime(int index) => DateTime.fromMillisecondsSinceEpoch(
    arrivalMilliseconds(index),
    isUtc: serviceDay.isUtc,
  );

  DateTime departureTime(int index) => DateTime.fromMillisecondsSinceEpoch(
    departureMilliseconds(index),
    isUtc: serviceDay.isUtc,
  );
}

bool _hasChronologicalStopTimes(List<StopTime> times) {
  int? previousDeparture;
  for (final time in times) {
    if (previousDeparture != null && time.arrivalSeconds < previousDeparture) {
      return false;
    }
    if (time.departureSeconds < time.arrivalSeconds) return false;
    previousDeparture = time.departureSeconds;
  }
  return true;
}

class _PatternDeparture {
  _PatternDeparture(this.instance, this.stopIndex)
    : departureMilliseconds = instance.departureMilliseconds(stopIndex);

  final _TripInstance instance;
  final int stopIndex;
  final int departureMilliseconds;
}

class _TransitPattern {
  const _TransitPattern({
    required this.id,
    required this.stopIds,
    required this.departuresByStop,
  });

  final String id;
  final List<String> stopIds;
  final List<List<_PatternDeparture>> departuresByStop;

  _PatternDeparture? nextDeparture(
    int stopIndex,
    DateTime earliest,
    DateTime latest,
    Set<String> excludedTripIds,
    _TransitSearchMetrics metrics,
  ) {
    final departures = departuresByStop[stopIndex];
    final earliestMilliseconds = earliest.millisecondsSinceEpoch;
    final latestMilliseconds = latest.millisecondsSinceEpoch;
    var low = 0;
    var high = departures.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      metrics.stopTimesRead++;
      if (departures[middle].departureMilliseconds < earliestMilliseconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    for (var index = low; index < departures.length; index++) {
      final candidate = departures[index];
      metrics.stopTimesRead++;
      if (candidate.departureMilliseconds > latestMilliseconds) return null;
      if (!excludedTripIds.contains(candidate.instance.trip.id)) {
        return candidate;
      }
    }
    return null;
  }
}

class _PatternBoarding {
  const _PatternBoarding(this.pattern, this.stopIndex);

  final _TransitPattern pattern;
  final int stopIndex;
}

class _RaptorRide {
  const _RaptorRide({
    required this.instance,
    required this.boardIndex,
    required this.alightIndex,
  });

  final _TripInstance instance;
  final int boardIndex;
  final int alightIndex;
}

class _RaptorLabel {
  const _RaptorLabel({
    required this.arrivalTime,
    required this.initialWalk,
    required this.rides,
    required this.transferWalks,
    required this.walkingMeters,
  });

  final DateTime arrivalTime;
  final _WalkingLeg initialWalk;
  final List<_RaptorRide> rides;
  final List<_WalkingLeg?> transferWalks;
  final double walkingMeters;
}

class _RaptorSeed {
  const _RaptorSeed({
    required this.stopId,
    required this.readyTime,
    required this.latestDeparture,
    required this.initialWalk,
    required this.walkingMeters,
    this.prefix,
    this.transferWalk,
  });

  final String stopId;
  final DateTime readyTime;
  final DateTime latestDeparture;
  final _WalkingLeg initialWalk;
  final double walkingMeters;
  final _RaptorLabel? prefix;
  final _WalkingLeg? transferWalk;
}

class _RaptorRoundResult {
  const _RaptorRoundResult(this.labelsByStop);

  final Map<String, List<_RaptorLabel>> labelsByStop;
}

class _WalkingGeometry {
  const _WalkingGeometry({
    required this.distanceMeters,
    required this.shape,
    required this.approximate,
    required this.gapMeters,
  });

  final double distanceMeters;
  final Shape shape;
  final bool approximate;
  final double gapMeters;
}

TripPlan _buildRaptorPlan(
  _RaptorLabel label,
  _WalkingLeg finalWalk,
  DateTime departureTime,
  double walkingMeters,
  Map<String, Stop> stopsById,
) {
  final legs = <TripLeg>[];
  if (label.initialWalk.distanceMeters > 1) {
    legs.add(label.initialWalk.toLeg());
  }
  for (var index = 0; index < label.rides.length; index++) {
    final ride = label.rides[index];
    final boardStop = stopsById[ride.instance.times[ride.boardIndex].stopId];
    if (index > 0) {
      final transferWalk = label.transferWalks[index - 1];
      if (transferWalk != null && transferWalk.distanceMeters > 1) {
        legs.add(transferWalk.toLeg());
      }
      final previousRide = label.rides[index - 1];
      final previousArrival = previousRide.instance.arrivalTime(
        previousRide.alightIndex,
      );
      legs.add(
        TripLeg(
          kind: TripLegKind.waiting,
          departureTime: transferWalk?.arrivalTime ?? previousArrival,
          arrivalTime: ride.instance.departureTime(ride.boardIndex),
          fromStop: transferWalk?.toStop ?? boardStop,
          toStop: boardStop,
        ),
      );
    } else {
      legs.add(
        TripLeg(
          kind: TripLegKind.waiting,
          departureTime: label.initialWalk.arrivalTime,
          arrivalTime: ride.instance.departureTime(ride.boardIndex),
          toStop: boardStop,
        ),
      );
    }
    legs.add(
      _transitLeg(ride.instance, ride.boardIndex, ride.alightIndex, stopsById),
    );
  }
  if (finalWalk.distanceMeters > 1) legs.add(finalWalk.toLeg());
  return TripPlan(
    requestedDeparture: departureTime,
    arrivalTime: finalWalk.arrivalTime,
    legs: legs,
    totalWalkingMeters: walkingMeters,
    transferCount: label.rides.length - 1,
  );
}

class _WalkingLeg {
  const _WalkingLeg({
    this.fromStop,
    this.toStop,
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toLatitude,
    required this.toLongitude,
    required this.distanceMeters,
    required this.departureTime,
    required this.arrivalTime,
    this.shape,
    this.approximate = false,
    this.gapMeters = 0,
  });

  final Stop? fromStop;
  final Stop? toStop;

  /// Geometría real del camino peatonal desde el origen hasta el destino.
  final Shape? shape;

  /// true si el tramo es estimado sin grafo peatonal (factor de desvío).
  final bool approximate;

  /// Distancia del punto real del usuario al punto proyectado donde empieza
  /// el camino real — 0 si no hay gap punteado.
  final double gapMeters;
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;
  final double distanceMeters;
  final DateTime departureTime;
  final DateTime arrivalTime;

  TripLeg toLeg() => TripLeg(
    kind: TripLegKind.walking,
    departureTime: departureTime,
    arrivalTime: arrivalTime,
    distanceMeters: distanceMeters,
    fromStop: fromStop,
    toStop: toStop,
    fromLatitude: fromLatitude,
    fromLongitude: fromLongitude,
    toLatitude: toLatitude,
    toLongitude: toLongitude,
    shape: shape,
    approximate: approximate,
    gapMeters: gapMeters,
  );

  _WalkingLeg copyWithTimes(DateTime departure, DateTime arrival) =>
      _WalkingLeg(
        fromStop: fromStop,
        toStop: toStop,
        fromLatitude: fromLatitude,
        fromLongitude: fromLongitude,
        toLatitude: toLatitude,
        toLongitude: toLongitude,
        distanceMeters: distanceMeters,
        departureTime: departure,
        arrivalTime: arrival,
        shape: shape,
        approximate: approximate,
        gapMeters: gapMeters,
      );
}
