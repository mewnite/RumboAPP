import 'dart:math' as math;

import '../../stops_and_lines/domain/transit_models.dart';
import '../../stops_and_lines/domain/transit_repository.dart';

class TripEndpoint {
  const TripEndpoint({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.stop,
  });

  factory TripEndpoint.fromStop(Stop stop) => TripEndpoint(
    name: stop.name,
    latitude: stop.latitude,
    longitude: stop.longitude,
    stop: stop,
  );

  final String name;
  final double latitude;
  final double longitude;
  final Stop? stop;
}

class TripRequest {
  const TripRequest({
    required this.originLatitude,
    required this.originLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.departureTime,
    this.maximumWalkingMeters = 1800,
    this.maximumTransfers = 1,
    this.maximumWait = const Duration(minutes: 45),
    this.walkingSpeedMetersPerSecond = 1.2,
    this.resultLimit = 5,
  });

  final double originLatitude;
  final double originLongitude;
  final double destinationLatitude;
  final double destinationLongitude;
  final DateTime departureTime;
  final double maximumWalkingMeters;
  final int maximumTransfers;
  final Duration maximumWait;
  final double walkingSpeedMetersPerSecond;
  final int resultLimit;
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
  const TransitTripPlanner(this._repository);

  final TransitRepository _repository;

  Future<List<TripPlan>> plan(TripRequest request) async {
    _validateRequest(request);
    final origins = await _repository.nearbyStops(
      request.originLatitude,
      request.originLongitude,
      request.maximumWalkingMeters,
    );
    final destinations = await _repository.nearbyStops(
      request.destinationLatitude,
      request.destinationLongitude,
      request.maximumWalkingMeters,
    );
    if (origins.isEmpty || destinations.isEmpty) return const [];

    final initialData = await _repository.scheduleForStops(
      origins.map((stop) => stop.id).toSet(),
    );
    final transferStopIds = initialData.stopTimes
        .map((time) => time.stopId)
        .where((id) => !origins.any((stop) => stop.id == id))
        .toSet();
    final additionalData = await _repository.scheduleForStops({
      ...transferStopIds,
      ...destinations.map((stop) => stop.id),
    });
    final data = _mergeScheduleData(initialData, additionalData);
    return const TransitRouteSearch().findPlans(
      request: request,
      data: data,
      originStopIds: origins.map((stop) => stop.id).toSet(),
      destinationStopIds: destinations.map((stop) => stop.id).toSet(),
    );
  }
}

class TransitRouteSearch {
  const TransitRouteSearch();

  List<TripPlan> findPlans({
    required TripRequest request,
    required TransitScheduleData data,
    required Set<String> originStopIds,
    required Set<String> destinationStopIds,
  }) {
    _validateRequest(request);
    if (originStopIds.isEmpty || destinationStopIds.isEmpty) return const [];

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
    final serviceDay = DateTime(
      request.departureTime.year,
      request.departureTime.month,
      request.departureTime.day,
    );
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
      for (final offset in [-1, 0]) {
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

    final plans = <TripPlan>[];
    for (final first in instances) {
      final firstTimes = first.absoluteTimes;
      for (
        var boardIndex = 0;
        boardIndex < first.times.length - 1;
        boardIndex++
      ) {
        final board = first.times[boardIndex];
        if (!originStopIds.contains(board.stopId)) continue;
        final boardStop = stopsById[board.stopId];
        if (boardStop == null) continue;
        final initialWalk = _walkingLeg(
          request.originLatitude,
          request.originLongitude,
          request.departureTime,
          request.walkingSpeedMetersPerSecond,
          toStop: boardStop,
          toLatitude: boardStop.latitude,
          toLongitude: boardStop.longitude,
        );
        final transitDeparture = firstTimes[boardIndex].departure;
        if (transitDeparture.isBefore(initialWalk.arrivalTime) ||
            transitDeparture.isAfter(
              initialWalk.arrivalTime.add(request.maximumWait),
            )) {
          continue;
        }

        for (
          var alightIndex = boardIndex + 1;
          alightIndex < first.times.length;
          alightIndex++
        ) {
          final alight = first.times[alightIndex];
          final alightStop = stopsById[alight.stopId];
          if (alightStop == null) continue;
          if (destinationStopIds.contains(alight.stopId)) {
            final finalWalk = _walkingLeg(
              alightStop.latitude,
              alightStop.longitude,
              firstTimes[alightIndex].arrival,
              request.walkingSpeedMetersPerSecond,
              fromStop: alightStop,
              toLatitude: request.destinationLatitude,
              toLongitude: request.destinationLongitude,
            );
            final walkingMeters =
                initialWalk.distanceMeters + finalWalk.distanceMeters;
            if (walkingMeters <= request.maximumWalkingMeters) {
              plans.add(
                _buildPlan(
                  request: request,
                  initialWalk: initialWalk,
                  finalWalk: finalWalk,
                  first: first,
                  firstBoardIndex: boardIndex,
                  firstAlightIndex: alightIndex,
                  firstTimes: firstTimes,
                  walkingMeters: walkingMeters,
                  stopsById: stopsById,
                ),
              );
            }
          }
          if (request.maximumTransfers < 1) continue;
          final connections =
              instancesByStop[alight.stopId] ?? <(_TripInstance, int)>[];
          for (final connection in connections) {
            final second = connection.$1;
            final secondBoardIndex = connection.$2;
            if (second.trip.id == first.trip.id) continue;
            final secondTimes = second.absoluteTimes;
            final nextDeparture = secondTimes[secondBoardIndex].departure;
            final wait = nextDeparture.difference(
              firstTimes[alightIndex].arrival,
            );
            if (wait.isNegative || wait > request.maximumWait) continue;
            for (
              var secondAlightIndex = secondBoardIndex + 1;
              secondAlightIndex < second.times.length;
              secondAlightIndex++
            ) {
              final finalStopTime = second.times[secondAlightIndex];
              if (!destinationStopIds.contains(finalStopTime.stopId)) continue;
              final finalStop = stopsById[finalStopTime.stopId];
              if (finalStop == null) continue;
              final finalWalk = _walkingLeg(
                finalStop.latitude,
                finalStop.longitude,
                secondTimes[secondAlightIndex].arrival,
                request.walkingSpeedMetersPerSecond,
                fromStop: finalStop,
                toLatitude: request.destinationLatitude,
                toLongitude: request.destinationLongitude,
              );
              final walkingMeters =
                  initialWalk.distanceMeters + finalWalk.distanceMeters;
              if (walkingMeters > request.maximumWalkingMeters) continue;
              plans.add(
                _buildPlan(
                  request: request,
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
                  walkingMeters: walkingMeters,
                  stopsById: stopsById,
                ),
              );
            }
          }
        }
      }
    }

    plans.sort((a, b) {
      final arrival = a.arrivalTime.compareTo(b.arrivalTime);
      if (arrival != 0) return arrival;
      final transfers = a.transferCount.compareTo(b.transferCount);
      if (transfers != 0) return transfers;
      return a.totalWalkingMeters.compareTo(b.totalWalkingMeters);
    });
    final unique = <String, TripPlan>{};
    for (final plan in plans) {
      final key = plan.legs
          .where((leg) => leg.kind == TripLegKind.transit)
          .map(
            (leg) => '${leg.route?.id}:${leg.departureTime.toIso8601String()}',
          )
          .join('|');
      unique.putIfAbsent(key, () => plan);
    }
    return unique.values.take(request.resultLimit).toList(growable: false);
  }
}

TripPlan _buildPlan({
  required TripRequest request,
  required _WalkingLeg initialWalk,
  required _WalkingLeg finalWalk,
  required _TripInstance first,
  required int firstBoardIndex,
  required int firstAlightIndex,
  required List<_AbsoluteStopTime> firstTimes,
  required double walkingMeters,
  required Map<String, Stop> stopsById,
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
    legs.add(
      TripLeg(
        kind: TripLegKind.waiting,
        departureTime: firstTimes[firstAlightIndex].arrival,
        arrivalTime: secondTimes[secondBoardIndex].departure,
        fromStop: stopsById[first.times[firstAlightIndex].stopId],
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
    requestedDeparture: request.departureTime,
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
  double speed, {
  Stop? fromStop,
  Stop? toStop,
  required double toLatitude,
  required double toLongitude,
}) {
  final meters = _distanceMeters(
    fromLatitude,
    fromLongitude,
    toLatitude,
    toLongitude,
  );
  return _WalkingLeg(
    fromStop: fromStop,
    toStop: toStop,
    fromLatitude: fromLatitude,
    fromLongitude: fromLongitude,
    toLatitude: toLatitude,
    toLongitude: toLongitude,
    distanceMeters: meters,
    departureTime: departure,
    arrivalTime: departure.add(Duration(seconds: (meters / speed).ceil())),
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

TransitScheduleData _mergeScheduleData(
  TransitScheduleData first,
  TransitScheduleData second,
) => TransitScheduleData(
  stops: _uniqueById([...first.stops, ...second.stops], (item) => item.id),
  routes: _uniqueById([...first.routes, ...second.routes], (item) => item.id),
  variants: _uniqueById([
    ...first.variants,
    ...second.variants,
  ], (item) => item.id),
  trips: _uniqueById([...first.trips, ...second.trips], (item) => item.id),
  stopTimes: _uniqueById([
    ...first.stopTimes,
    ...second.stopTimes,
  ], (item) => '${item.tripId}:${item.sequence}'),
  calendars: _uniqueById([
    ...first.calendars,
    ...second.calendars,
  ], (item) => item.serviceId),
);

List<T> _uniqueById<T>(Iterable<T> values, String Function(T) id) {
  final unique = <String, T>{};
  for (final value in values) {
    unique.putIfAbsent(id(value), () => value);
  }
  return unique.values.toList(growable: false);
}

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
  if (!request.maximumWalkingMeters.isFinite ||
      request.maximumWalkingMeters < 0 ||
      !request.walkingSpeedMetersPerSecond.isFinite ||
      request.walkingSpeedMetersPerSecond <= 0 ||
      request.maximumTransfers < 0 ||
      request.maximumTransfers > 1 ||
      request.resultLimit < 0 ||
      request.maximumWait.isNegative) {
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
}
