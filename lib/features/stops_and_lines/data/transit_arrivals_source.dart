import 'dart:math' as math;

import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';

class TransitArrivalsSource implements ArrivalsSource {
  const TransitArrivalsSource(
    this.repository, {
    this.liveSource,
    this.livePositions,
  });

  final TransitRepository repository;
  final RealtimeBusSource? liveSource;
  final List<BusPosition>? livePositions;

  @override
  Future<List<StopArrival>> arrivalsForStop(
    String stopId,
    DateTime now, {
    int limit = 8,
  }) async {
    final safeLimit = limit.clamp(1, 8);
    final scheduled = await repository.upcomingDepartures(
      stopId,
      now,
      limit: 50,
    );
    final routes = await repository.routesForStop(stopId);
    final routesById = {for (final route in routes) route.id: route};
    final scheduledArrivals = [
      for (final departure in scheduled)
        StopArrival(
          stopId: stopId,
          routeId: departure.trip.routeId,
          routeLabel:
              routesById[departure.trip.routeId]?.shortName.isNotEmpty == true
              ? routesById[departure.trip.routeId]!.shortName
              : departure.trip.routeId,
          destination: departure.trip.headsign,
          departureTime: departure.departure,
          variantId: departure.trip.variantId,
        ),
    ];

    if (livePositions == null && liveSource == null) {
      return _ordered(scheduledArrivals, safeLimit);
    }

    try {
      final positions = livePositions ?? (await liveSource!.fetch()).positions;
      final matchingVariantIds = <int>{};
      for (final route in routes) {
        final variants = await repository.variantsForRoute(route.id);
        matchingVariantIds.addAll(
          variants.map((variant) => variant.externalVariantId).whereType<int>(),
        );
      }
      final snapshot = RealtimeSnapshot(
        positions: positions
            .where(
              (position) =>
                  matchingVariantIds.contains(position.variantId) &&
                  now.difference(position.receivedAt) <=
                      const Duration(seconds: 60),
            )
            .toList(growable: false),
        discardedCount: 0,
        discardReasons: const {},
      );
      final matches = await RealtimeMatcher(repository).match(snapshot);
      final liveByVariant = <String, StopArrival>{};
      final stop = await repository.stopById(stopId);
      if (stop == null) return _ordered(scheduledArrivals, safeLimit);

      for (final match in matches) {
        final route = match.route;
        final variant = match.variant;
        final position = match.position;
        if (route == null ||
            variant == null ||
            !routesById.containsKey(route.id) ||
            now.difference(position.receivedAt) > const Duration(seconds: 60)) {
          continue;
        }
        final shape = await repository.shapeForVariant(variant.id);
        if (shape == null) continue;
        final minutes = estimateBusArrivalMinutes(
          position: position,
          stop: stop,
          shape: shape,
        );
        if (minutes == null) continue;

        final key = '${route.id}|${variant.id}';
        final candidate = StopArrival(
          stopId: stopId,
          routeId: route.id,
          routeLabel: route.shortName.isEmpty ? route.id : route.shortName,
          destination: variant.destination.isEmpty
              ? route.longName
              : variant.destination,
          departureTime: now.add(Duration(minutes: minutes)),
          variantId: variant.id,
          isLive: true,
          liveSourceId: position.sourceId.toString(),
        );
        final previous = liveByVariant[key];
        if (previous == null ||
            candidate.departureTime.isBefore(previous.departureTime)) {
          liveByVariant[key] = candidate;
        }
      }

      final merged = <StopArrival>[];
      for (final arrival in scheduledArrivals) {
        final key = '${arrival.routeId}|${arrival.variantId}';
        merged.add(liveByVariant.remove(key) ?? arrival);
      }
      merged.addAll(liveByVariant.values);
      return _ordered(merged, safeLimit);
    } on Exception {
      return _ordered(scheduledArrivals, safeLimit);
    }
  }

  List<StopArrival> _ordered(List<StopArrival> arrivals, int limit) {
    arrivals.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return arrivals.take(limit).toList(growable: false);
  }
}

int? estimateBusArrivalMinutes({
  required BusPosition position,
  required Stop stop,
  required Shape shape,
}) {
  if (shape.points.length < 2) return null;

  final bus = _projectOntoShape(
    position.latitude,
    position.longitude,
    shape,
    stop.latitude,
  );
  final stopProjection = _projectOntoShape(
    stop.latitude,
    stop.longitude,
    shape,
    stop.latitude,
  );
  if (bus == null ||
      stopProjection == null ||
      bus.distanceAlong >= stopProjection.distanceAlong) {
    return null;
  }

  final speedKmh = position.speedKmh >= 8 ? position.speedKmh : 18;
  final seconds =
      (stopProjection.distanceAlong - bus.distanceAlong) / (speedKmh / 3.6);
  return (seconds / 60).ceil();
}

class _ShapeProjection {
  const _ShapeProjection(this.distanceFromShape, this.distanceAlong);

  final double distanceFromShape;
  final double distanceAlong;
}

_ShapeProjection? _projectOntoShape(
  double latitude,
  double longitude,
  Shape shape,
  double referenceLatitude,
) {
  if (shape.points.length < 2) return null;
  const metersPerLatitudeDegree = 111132.92;
  final metersPerLongitudeDegree =
      111412.84 * math.cos(referenceLatitude * math.pi / 180);
  final pointX = longitude * metersPerLongitudeDegree;
  final pointY = latitude * metersPerLatitudeDegree;
  var distanceAlong = 0.0;
  var bestDistance = double.infinity;
  var bestDistanceAlong = 0.0;

  for (var index = 0; index < shape.points.length - 1; index++) {
    final start = shape.points[index];
    final end = shape.points[index + 1];
    final startX = start.longitude * metersPerLongitudeDegree;
    final startY = start.latitude * metersPerLatitudeDegree;
    final deltaX = (end.longitude - start.longitude) * metersPerLongitudeDegree;
    final deltaY = (end.latitude - start.latitude) * metersPerLatitudeDegree;
    final segmentLengthSquared = deltaX * deltaX + deltaY * deltaY;
    final segmentLength = math.sqrt(segmentLengthSquared);
    final fraction = segmentLengthSquared == 0
        ? 0.0
        : (((pointX - startX) * deltaX + (pointY - startY) * deltaY) /
                  segmentLengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
    final projectedX = startX + fraction * deltaX;
    final projectedY = startY + fraction * deltaY;
    final distance = math.sqrt(
      math.pow(pointX - projectedX, 2) + math.pow(pointY - projectedY, 2),
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      bestDistanceAlong = distanceAlong + fraction * segmentLength;
    }
    distanceAlong += segmentLength;
  }

  if (!bestDistance.isFinite) return null;
  return _ShapeProjection(bestDistance, bestDistanceAlong);
}
