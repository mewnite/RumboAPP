import 'dart:math' as math;

import '../../../core/debug/performance_measurement.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../../stops_and_lines/domain/transit_repository.dart';
import 'plan_search_isolate.dart';
import 'planner_config.dart';

class TripEndpoint {
  const TripEndpoint({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.stop,
    this.route,
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
    this.headsign = '',
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
  final String headsign;
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
  const TransitTripPlanner(this._repository, {this.now});

  final TransitRepository _repository;
  final DateTime Function()? now;

  Future<List<TripPlan>> plan(TripRequest request) async {
    final measurement = PerformanceMeasurement.start('trip.plan');
    _validateRequest(request);
    final current = now?.call() ?? DateTime.now();
    if (request.timing.isPast(current)) return const [];
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
    final nearbyEndpoints = await Future.wait([
      _repository.nearbyStops(
        request.originLatitude,
        request.originLongitude,
        config.maximumWalkingMeters,
      ),
      _repository.nearbyStops(
        request.destinationLatitude,
        request.destinationLongitude,
        config.maximumWalkingMeters,
      ),
    ]);
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
      data = await _repository.scheduleForStops(
        relevantStopIds,
        windowStart: scheduleWindowStart,
        windowEnd: scheduleWindowEnd,
      );
    }

    final plans = await runPlanSearch(
      PlanSearchPayload(
        request: request,
        data: data,
        originStopIds: origins.map((stop) => stop.id).toSet(),
        destinationStopIds: destinations.map((stop) => stop.id).toSet(),
        now: current,
      ),
    );
    measurement.finish(details: 'plans=${plans.length}');
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
List<TripPlan> searchPlansSync(PlanSearchPayload payload) =>
    const TransitRouteSearch().findPlans(
      request: payload.request,
      data: payload.data,
      originStopIds: payload.originStopIds,
      destinationStopIds: payload.destinationStopIds,
      now: payload.now,
    );

const _arrivalSearchStepMinutes = 10;
const _arrivalSearchWindowMinutes = 180;
const _maximumEndpointStopCandidates = 8;

class TransitRouteSearch {
  const TransitRouteSearch();

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

    final walkingOnly = _walkingOnlyPlan(request, clock);
    final transitPlans = _findTransitPlans(
      request: request,
      data: data,
      originStopIds: originStopIds,
      destinationStopIds: destinationStopIds,
      clock: clock,
    );
    return _finalizePlans([?walkingOnly, ...transitPlans], request);
  }

  List<TripPlan> _findTransitPlans({
    required TripRequest request,
    required TransitScheduleData data,
    required Set<String> originStopIds,
    required Set<String> destinationStopIds,
    required DateTime clock,
  }) {
    if (originStopIds.isEmpty || destinationStopIds.isEmpty) return const [];
    final indexCache = <DateTime, _ScheduleIndex>{};
    switch (request.timing.mode) {
      case TripTimingMode.departNow:
        return _findForward(
          request: request.copyWith(timing: TripTiming.departAt(clock)),
          data: data,
          originStopIds: originStopIds,
          destinationStopIds: destinationStopIds,
          indexCache: indexCache,
        );
      case TripTimingMode.departAt:
        return _findForward(
          request: request,
          data: data,
          originStopIds: originStopIds,
          destinationStopIds: destinationStopIds,
          indexCache: indexCache,
        );
      case TripTimingMode.arriveBy:
        final target = request.timing.dateTime!;
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
  }) {
    final departureTime = request.departureTime;
    if (departureTime == null) return const [];
    final serviceDay = DateTime(
      departureTime.year,
      departureTime.month,
      departureTime.day,
    );
    final index = indexCache.putIfAbsent(
      serviceDay,
      () => _ScheduleIndex.build(data, serviceDay),
    );
    final config = request.config;
    final transferTargetsByStop = <String, List<_TransferTarget>>{};
    final destinationIndicesByInstance = <_TripInstance, List<int>>{};
    for (final instance in index.instances) {
      for (var stopIndex = 0; stopIndex < instance.times.length; stopIndex++) {
        if (destinationStopIds.contains(instance.times[stopIndex].stopId)) {
          destinationIndicesByInstance
              .putIfAbsent(instance, () => <int>[])
              .add(stopIndex);
        }
      }
    }

    final plans = <TripPlan>[];
    for (final originStopId in originStopIds) {
      final boardStop = index.stopsById[originStopId];
      if (boardStop == null) continue;
      final initialWalk = _walkingLeg(
        request.originLatitude,
        request.originLongitude,
        departureTime,
        config,
        toStop: boardStop,
        toLatitude: boardStop.latitude,
        toLongitude: boardStop.longitude,
      );
      final originConnections = index.connectionsBetween(
        originStopId,
        initialWalk.arrivalTime,
        initialWalk.arrivalTime.add(config.maximumWait),
      );
      for (final originConnection in originConnections) {
        final first = originConnection.$1;
        final boardIndex = originConnection.$2;
        final firstTimes = first.absoluteTimes;

        for (
          var alightIndex = boardIndex + 1;
          alightIndex < first.times.length;
          alightIndex++
        ) {
          final alight = first.times[alightIndex];
          final alightStop = index.stopsById[alight.stopId];
          if (alightStop == null) continue;
          if (destinationStopIds.contains(alight.stopId)) {
            final finalWalk = _walkingLeg(
              alightStop.latitude,
              alightStop.longitude,
              firstTimes[alightIndex].arrival,
              config,
              fromStop: alightStop,
              toLatitude: request.destinationLatitude,
              toLongitude: request.destinationLongitude,
            );
            final walkingMeters =
                initialWalk.distanceMeters + finalWalk.distanceMeters;
            if (walkingMeters <= config.maximumWalkingMeters) {
              plans.add(
                _buildPlan(
                  departureTime: departureTime,
                  initialWalk: initialWalk,
                  finalWalk: finalWalk,
                  first: first,
                  firstBoardIndex: boardIndex,
                  firstAlightIndex: alightIndex,
                  firstTimes: firstTimes,
                  walkingMeters: walkingMeters,
                  stopsById: index.stopsById,
                ),
              );
            }
          }
          if (config.maximumTransfers < 1) continue;
          final targets = transferTargetsByStop.putIfAbsent(
            alightStop.id,
            () => _transferTargets(alightStop, index, config),
          );
          for (final target in targets) {
            final transferArrival = firstTimes[alightIndex].arrival;
            final transferWalk = target.stop.id == alightStop.id
                ? null
                : _walkingLeg(
                    alightStop.latitude,
                    alightStop.longitude,
                    transferArrival,
                    config,
                    fromStop: alightStop,
                    toStop: target.stop,
                    toLatitude: target.stop.latitude,
                    toLongitude: target.stop.longitude,
                  );
            final readyTime = transferWalk?.arrivalTime ?? transferArrival;
            final minimumDeparture = transferArrival.add(
              config.minimumTransferTime,
            );
            final earliestDeparture = readyTime.isAfter(minimumDeparture)
                ? readyTime
                : minimumDeparture;
            final latestDeparture = transferArrival.add(config.maximumWait);
            if (earliestDeparture.isAfter(latestDeparture)) continue;
            final connections = index.connectionsBetween(
              target.stop.id,
              earliestDeparture,
              latestDeparture,
            );
            for (final connection in connections) {
              final second = connection.$1;
              final secondBoardIndex = connection.$2;
              if (second.trip.id == first.trip.id) continue;
              final secondTimes = second.absoluteTimes;
              for (final secondAlightIndex
                  in destinationIndicesByInstance[second] ?? const <int>[]) {
                if (secondAlightIndex <= secondBoardIndex) continue;
                final finalStopTime = second.times[secondAlightIndex];
                final finalStop = index.stopsById[finalStopTime.stopId];
                if (finalStop == null) continue;
                final finalWalk = _walkingLeg(
                  finalStop.latitude,
                  finalStop.longitude,
                  secondTimes[secondAlightIndex].arrival,
                  config,
                  fromStop: finalStop,
                  toLatitude: request.destinationLatitude,
                  toLongitude: request.destinationLongitude,
                );
                final walkingMeters =
                    initialWalk.distanceMeters +
                    finalWalk.distanceMeters +
                    (transferWalk?.distanceMeters ?? 0);
                if (walkingMeters > config.maximumWalkingMeters) continue;
                plans.add(
                  _buildPlan(
                    departureTime: departureTime,
                    initialWalk: initialWalk,
                    finalWalk: finalWalk,
                    first: first,
                    firstBoardIndex: boardIndex,
                    firstAlightIndex: alightIndex,
                    firstTimes: firstTimes,
                    second: second,
                    secondBoardIndex: secondBoardIndex,
                    secondAlightIndex: secondAlightIndex,
                    secondTimes: secondTimes,
                    transferWalk: transferWalk,
                    walkingMeters: walkingMeters,
                    stopsById: index.stopsById,
                  ),
                );
              }
            }
          }
        }
      }
    }
    return plans;
  }

  List<_TransferTarget> _transferTargets(
    Stop from,
    _ScheduleIndex index,
    PlannerConfig config,
  ) {
    final targets = <_TransferTarget>[];
    for (final stop in index.nearbyStops(
      from,
      config.maximumTransferWalkingMeters,
    )) {
      if (stop.id == from.id) {
        targets.add(_TransferTarget(stop));
        continue;
      }
      final meters = _distanceMeters(
        from.latitude,
        from.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (meters <= config.maximumTransferWalkingMeters) {
        targets.add(_TransferTarget(stop));
      }
    }
    return targets;
  }

  TripPlan? _walkingOnlyPlan(TripRequest request, DateTime clock) {
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
}

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
  var fastestNoTransferWalking = double.infinity;
  var fastestOneTransferWalking = double.infinity;
  for (final plan in unique.values) {
    final minimumWalking = plan.transferCount == 0
        ? fastestNoTransferWalking
        : math.min(fastestNoTransferWalking, fastestOneTransferWalking);
    if (minimumWalking <= plan.totalWalkingMeters) continue;
    kept.add(plan);
    if (plan.transferCount == 0) {
      fastestNoTransferWalking = math.min(
        fastestNoTransferWalking,
        plan.totalWalkingMeters,
      );
    } else {
      fastestOneTransferWalking = math.min(
        fastestOneTransferWalking,
        plan.totalWalkingMeters,
      );
    }
  }
  return kept.take(request.config.resultLimit).toList(growable: false);
}

class _ScheduleIndex {
  const _ScheduleIndex._({
    required this.stopsById,
    required this.instances,
    required this.instancesByStop,
    required this.stopsByCell,
    required this.cellSizeDegrees,
  });

  factory _ScheduleIndex.build(TransitScheduleData data, DateTime serviceDay) {
    final stopsById = {for (final stop in data.stops) stop.id: stop};
    final routesById = {for (final route in data.routes) route.id: route};
    final variantsById = {
      for (final variant in data.variants) variant.id: variant,
    };
    final calendarsById = {
      for (final calendar in data.calendars) calendar.serviceId: calendar,
    };
    final timesByTrip = <String, List<StopTime>>{};
    for (final time in data.stopTimes) {
      timesByTrip.putIfAbsent(time.tripId, () => []).add(time);
    }
    for (final times in timesByTrip.values) {
      times.sort((a, b) => a.sequence.compareTo(b.sequence));
    }

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
      for (final offset in [-1, 0, 1]) {
        final day = serviceDay.add(Duration(days: offset));
        if (!calendar.activeOn(day)) continue;
        instances.add(
          _TripInstance(
            trip: trip,
            route: route,
            variant: variantsById[trip.variantId],
            times: times,
            absoluteTimes: times
                .map(
                  (time) => _AbsoluteStopTime(
                    arrival: day.add(Duration(seconds: time.arrivalSeconds)),
                    departure: day.add(
                      Duration(seconds: time.departureSeconds),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        );
      }
    }
    final instancesByStop = <String, List<(_TripInstance, int)>>{};
    for (final instance in instances) {
      for (var index = 0; index < instance.times.length - 1; index++) {
        instancesByStop
            .putIfAbsent(
              instance.times[index].stopId,
              () => <(_TripInstance, int)>[],
            )
            .add((instance, index));
      }
    }
    for (final connections in instancesByStop.values) {
      connections.sort((first, second) {
        final firstDeparture = first.$1.absoluteTimes[first.$2].departure;
        final secondDeparture = second.$1.absoluteTimes[second.$2].departure;
        return firstDeparture.compareTo(secondDeparture);
      });
    }
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
    return _ScheduleIndex._(
      stopsById: stopsById,
      instances: instances,
      instancesByStop: instancesByStop,
      stopsByCell: stopsByCell,
      cellSizeDegrees: cellSizeDegrees,
    );
  }

  final Map<String, Stop> stopsById;
  final List<_TripInstance> instances;
  final Map<String, List<(_TripInstance, int)>> instancesByStop;
  final Map<(int, int), List<Stop>> stopsByCell;
  final double cellSizeDegrees;

  Iterable<(_TripInstance, int)> connectionsBetween(
    String stopId,
    DateTime earliest,
    DateTime latest,
  ) sync* {
    final connections = instancesByStop[stopId];
    if (connections == null) return;
    var low = 0;
    var high = connections.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      final departure = connections[middle]
          .$1
          .absoluteTimes[connections[middle].$2]
          .departure;
      if (departure.isBefore(earliest)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low; index < connections.length; index++) {
      final connection = connections[index];
      final departure = connection.$1.absoluteTimes[connection.$2].departure;
      if (departure.isAfter(latest)) break;
      yield connection;
    }
  }

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

TripPlan _buildPlan({
  required DateTime departureTime,
  required _WalkingLeg initialWalk,
  required _WalkingLeg finalWalk,
  required _TripInstance first,
  required int firstBoardIndex,
  required int firstAlightIndex,
  required List<_AbsoluteStopTime> firstTimes,
  required double walkingMeters,
  required Map<String, Stop> stopsById,
  _WalkingLeg? transferWalk,
  _TripInstance? second,
  int? secondBoardIndex,
  int? secondAlightIndex,
  List<_AbsoluteStopTime>? secondTimes,
}) {
  final legs = <TripLeg>[];
  if (initialWalk.distanceMeters > 1) {
    legs.add(initialWalk.toLeg());
  }
  legs.add(
    TripLeg(
      kind: TripLegKind.waiting,
      departureTime: initialWalk.arrivalTime,
      arrivalTime: firstTimes[firstBoardIndex].departure,
      toStop: stopsById[first.times[firstBoardIndex].stopId],
    ),
  );
  legs.add(
    _transitLeg(
      first,
      firstBoardIndex,
      firstAlightIndex,
      firstTimes,
      stopsById,
    ),
  );
  if (second != null &&
      secondBoardIndex != null &&
      secondAlightIndex != null &&
      secondTimes != null) {
    if (transferWalk != null && transferWalk.distanceMeters > 1) {
      legs.add(transferWalk.toLeg());
    }
    final transferArrival =
        transferWalk?.arrivalTime ?? firstTimes[firstAlightIndex].arrival;
    legs.add(
      TripLeg(
        kind: TripLegKind.waiting,
        departureTime: transferArrival,
        arrivalTime: secondTimes[secondBoardIndex].departure,
        fromStop:
            transferWalk?.toStop ??
            stopsById[first.times[firstAlightIndex].stopId],
      ),
    );
    legs.add(
      _transitLeg(
        second,
        secondBoardIndex,
        secondAlightIndex,
        secondTimes,
        stopsById,
      ),
    );
  }
  if (finalWalk.distanceMeters > 1) legs.add(finalWalk.toLeg());
  return TripPlan(
    requestedDeparture: departureTime,
    arrivalTime: finalWalk.arrivalTime,
    legs: legs,
    totalWalkingMeters: walkingMeters,
    transferCount: second == null ? 0 : 1,
  );
}

TripLeg _transitLeg(
  _TripInstance instance,
  int boardIndex,
  int alightIndex,
  List<_AbsoluteStopTime> absoluteTimes,
  Map<String, Stop> stopsById,
) => TripLeg(
  kind: TripLegKind.transit,
  departureTime: absoluteTimes[boardIndex].departure,
  arrivalTime: absoluteTimes[alightIndex].arrival,
  fromStop: stopsById[instance.times[boardIndex].stopId],
  toStop: stopsById[instance.times[alightIndex].stopId],
  route: instance.route,
  variant: instance.variant,
  headsign: instance.trip.headsign,
);

_WalkingLeg _walkingLeg(
  double fromLatitude,
  double fromLongitude,
  DateTime departure,
  PlannerConfig config, {
  Stop? fromStop,
  Stop? toStop,
  required double toLatitude,
  required double toLongitude,
}) {
  final straightMeters = _distanceMeters(
    fromLatitude,
    fromLongitude,
    toLatitude,
    toLongitude,
  );
  final meters = straightMeters * config.detourFactor;
  return _WalkingLeg(
    fromStop: fromStop,
    toStop: toStop,
    fromLatitude: fromLatitude,
    fromLongitude: fromLongitude,
    toLatitude: toLatitude,
    toLongitude: toLongitude,
    distanceMeters: meters,
    departureTime: departure,
    arrivalTime: departure.add(
      Duration(seconds: (meters / config.walkingSpeedMetersPerSecond).ceil()),
    ),
  );
}

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
      config.maximumTransfers > 1 ||
      config.resultLimit < 0 ||
      config.maximumWait.isNegative) {
    throw ArgumentError('Los parámetros del viaje no son válidos.');
  }
}

class _TripInstance {
  const _TripInstance({
    required this.trip,
    required this.route,
    required this.variant,
    required this.times,
    required this.absoluteTimes,
  });

  final Trip trip;
  final Route route;
  final RouteVariant? variant;
  final List<StopTime> times;
  final List<_AbsoluteStopTime> absoluteTimes;
}

class _AbsoluteStopTime {
  const _AbsoluteStopTime({required this.arrival, required this.departure});

  final DateTime arrival;
  final DateTime departure;
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
  });

  final Stop? fromStop;
  final Stop? toStop;
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
      );
}

class _TransferTarget {
  const _TransferTarget(this.stop);

  final Stop stop;
}
