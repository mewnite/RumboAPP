class Stop {
  const Stop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.code = '',
    this.description = '',
  });
  final String id, name, code, description;
  final double latitude, longitude;
}

class Route {
  const Route({
    required this.id,
    required this.shortName,
    this.longName = '',
    this.color = '',
    this.textColor = '',
    this.realtimeKey,
  });
  final String id, shortName, longName, color, textColor;
  final String? realtimeKey;
}

class RouteVariant {
  const RouteVariant({
    required this.id,
    required this.routeId,
    required this.directionId,
    required this.destination,
    this.shapeId,
    this.externalVariantId,
  });
  final String id, routeId, directionId, destination;
  final String? shapeId;

  /// STM variant code used to join an online vehicle to this static variant.
  final int? externalVariantId;
}

class Trip {
  const Trip({
    required this.id,
    required this.routeId,
    required this.serviceId,
    required this.variantId,
    this.headsign = '',
  });
  final String id, routeId, serviceId, variantId, headsign;
}

class StopTime {
  const StopTime({
    required this.tripId,
    required this.stopId,
    required this.arrivalSeconds,
    required this.departureSeconds,
    required this.sequence,
  });
  final String tripId, stopId;

  /// Seconds from the service-day start; may exceed 86400 per GTFS.
  final int arrivalSeconds, departureSeconds, sequence;
}

class ShapePoint {
  const ShapePoint(this.latitude, this.longitude, this.sequence);
  final double latitude, longitude;
  final int sequence;
}

class Shape {
  const Shape({required this.id, required this.points});
  final String id;
  final List<ShapePoint> points;
}

class ServiceCalendar {
  const ServiceCalendar({
    required this.serviceId,
    required this.startDate,
    required this.endDate,
    required this.weekdays,
    this.addedDates = const {},
    this.removedDates = const {},
  });
  final String serviceId;
  final DateTime startDate, endDate;

  /// DateTime.weekday values (Monday=1 … Sunday=7).
  final Set<int> weekdays;
  final Set<DateTime> addedDates, removedDates;

  bool activeOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (removedDates.contains(day)) return false;
    if (addedDates.contains(day)) return true;
    return !day.isBefore(startDate) &&
        !day.isAfter(endDate) &&
        weekdays.contains(day.weekday);
  }
}

class FeedInfo {
  const FeedInfo({
    this.publisherName = '',
    this.publisherUrl = '',
    this.version = '',
    this.startDate,
    this.endDate,
    this.language = '',
    this.synthetic = false,
  });
  final String publisherName, publisherUrl, version, language;
  final DateTime? startDate, endDate;
  final bool synthetic;
}

class UpcomingDeparture {
  const UpcomingDeparture({
    required this.trip,
    required this.stopTime,
    required this.departure,
  });
  final Trip trip;
  final StopTime stopTime;
  final DateTime departure;
}

class StopArrival {
  const StopArrival({
    required this.stopId,
    required this.routeId,
    required this.routeLabel,
    required this.destination,
    required this.departureTime,
    this.variantId,
    this.isLive = false,
    this.liveSourceId,
  });

  final String stopId;
  final String routeId;
  final String routeLabel;
  final String destination;
  final DateTime departureTime;
  final String? variantId;
  final bool isLive;
  final String? liveSourceId;

  Duration get timeUntil => departureTime.difference(DateTime.now());
}

class TransitScheduleData {
  const TransitScheduleData({
    this.stops = const [],
    this.routes = const [],
    this.variants = const [],
    this.trips = const [],
    this.stopTimes = const [],
    this.calendars = const [],
  });

  final List<Stop> stops;
  final List<Route> routes;
  final List<RouteVariant> variants;
  final List<Trip> trips;
  final List<StopTime> stopTimes;
  final List<ServiceCalendar> calendars;
}

class FeedStatus {
  const FeedStatus({
    this.source = '',
    this.version = '',
    this.downloadedAt,
    this.validUntil,
    this.etag,
    this.stopCount = 0,
    this.routeCount = 0,
    this.variantCount = 0,
    this.tripCount = 0,
    this.stopTimeCount = 0,
    this.shapePointCount = 0,
    this.calendarCount = 0,
    this.synthetic = false,
    this.warningCount = 0,
    this.stale = false,
  });
  final String source, version;
  final DateTime? downloadedAt, validUntil;
  final String? etag;
  final int stopCount, routeCount, warningCount;
  final int variantCount,
      tripCount,
      stopTimeCount,
      shapePointCount,
      calendarCount;
  final bool synthetic;
  final bool stale;
}

bool isFeedExpired(DateTime? validUntil, DateTime now) =>
    validUntil?.isBefore(now) ?? false;

class BusPosition {
  const BusPosition({
    required this.sourceId,
    required this.companyCode,
    required this.busCode,
    required this.variantId,
    required this.lineLabel,
    required this.sublineDescription,
    required this.destinationCode,
    required this.destinationName,
    required this.lineTypeCode,
    required this.lineTypeName,
    required this.subsystemCode,
    required this.subsystemName,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.receivedAt,
    this.rawExtras = const {},
  });

  /// Kept as received; its format can change when a unit changes variant.
  final Object sourceId;
  final int companyCode, busCode, variantId;
  final String lineLabel, sublineDescription, destinationCode, destinationName;
  final int lineTypeCode, subsystemCode;
  final String lineTypeName, subsystemName;
  final double latitude, longitude;
  final double speedKmh;
  final DateTime receivedAt;
  final Map<String, Object?> rawExtras;
}

class RealtimeSnapshot {
  const RealtimeSnapshot({
    required this.positions,
    required this.discardedCount,
    required this.discardReasons,
    this.duplicateCount = 0,
  });
  final List<BusPosition> positions;
  final int discardedCount, duplicateCount;
  final Map<String, int> discardReasons;
}

class MatchedBusPosition {
  const MatchedBusPosition(this.position, {this.variant, this.route});
  final BusPosition position;
  final RouteVariant? variant;
  final Route? route;
  bool get hasRoute => route != null;
}
