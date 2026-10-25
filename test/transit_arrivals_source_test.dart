import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/fake_transit_repository.dart';
import 'package:rumbo/features/stops_and_lines/data/transit_arrivals_source.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';

const _stop = Stop(
  id: 's1',
  name: 'Parada de prueba',
  code: '1',
  latitude: -34.885,
  longitude: -56.10,
);

const _shape = Shape(
  id: 'shape1',
  points: [ShapePoint(-34.90, -56.10, 1), ShapePoint(-34.88, -56.10, 2)],
);

void main() {
  test('projects the bus onto its shape and estimates the arrival', () {
    final stopped = _bus(
      variantId: 101,
      latitude: -34.895,
      longitude: -56.1003,
      speedKmh: 0,
      receivedAt: DateTime(2026, 10, 26, 12),
    );
    final moving = _bus(
      variantId: 101,
      latitude: -34.895,
      longitude: -56.10,
      speedKmh: 36,
      receivedAt: DateTime(2026, 10, 26, 12),
    );

    expect(
      estimateBusArrivalMinutes(position: stopped, stop: _stop, shape: _shape),
      4,
    );
    expect(
      estimateBusArrivalMinutes(position: moving, stop: _stop, shape: _shape),
      2,
    );
  });

  test('discards a bus that already passed the stop', () {
    final passed = _bus(
      variantId: 101,
      latitude: -34.88,
      longitude: -56.10,
      receivedAt: DateTime(2026, 10, 26, 12),
    );

    expect(
      estimateBusArrivalMinutes(position: passed, stop: _stop, shape: _shape),
      isNull,
    );
  });

  test(
    'live arrivals replace the next scheduled departure of their variant',
    () async {
      final repository = _repository();
      final now = DateTime(2026, 10, 26, 12);
      final source = TransitArrivalsSource(
        repository,
        livePositions: [
          _bus(
            variantId: 101,
            latitude: -34.895,
            longitude: -56.10,
            receivedAt: now.subtract(const Duration(seconds: 10)),
          ),
        ],
      );

      final arrivals = await source.arrivalsForStop('s1', now, limit: 8);

      expect(arrivals, hasLength(3));
      expect(arrivals.first.isLive, isTrue);
      expect(arrivals.first.routeLabel, 'A');
      expect(arrivals.first.destination, 'Centro');
      expect(arrivals.first.departureTime, now.add(const Duration(minutes: 4)));
      expect(arrivals[1].isLive, isFalse);
      expect(arrivals[1].routeLabel, 'B');
      expect(arrivals[1].departureTime, DateTime(2026, 10, 26, 12, 15));
      expect(arrivals.last.isLive, isFalse);
      expect(arrivals.last.routeLabel, 'A');
      expect(arrivals.last.departureTime, DateTime(2026, 10, 26, 12, 20));
      expect(arrivals.map((arrival) => arrival.departureTime).toList(), [
        now.add(const Duration(minutes: 4)),
        DateTime(2026, 10, 26, 12, 15),
        DateTime(2026, 10, 26, 12, 20),
      ]);
    },
  );

  test('falls back to scheduled departures ordered by time', () async {
    final repository = _repository();
    final now = DateTime(2026, 10, 26, 12);

    final arrivals = await TransitArrivalsSource(repository)
        .arrivalsForStop('s1', now, limit: 8);

    expect(arrivals.map((arrival) => arrival.isLive), everyElement(isFalse));
    expect(arrivals.map((arrival) => arrival.departureTime).toList(), [
      DateTime(2026, 10, 26, 12, 10),
      DateTime(2026, 10, 26, 12, 15),
      DateTime(2026, 10, 26, 12, 20),
    ]);
  });
}

FakeTransitRepository _repository() {
  const serviceId = 'service';
  final repository = FakeTransitRepository(
    stops: const [_stop],
    routes: const [
      Route(id: 'r1', shortName: 'A', longName: 'Centro'),
      Route(id: 'r2', shortName: 'B', longName: 'Sur'),
    ],
    variants: const [
      RouteVariant(
        id: 'v1',
        routeId: 'r1',
        directionId: '0',
        destination: 'Centro',
        shapeId: 'shape1',
        externalVariantId: 101,
      ),
      RouteVariant(
        id: 'v2',
        routeId: 'r2',
        directionId: '0',
        destination: 'Sur',
        shapeId: 'shape1',
        externalVariantId: 102,
      ),
    ],
    trips: const [
      Trip(
        id: 't1',
        routeId: 'r1',
        serviceId: serviceId,
        variantId: 'v1',
        headsign: 'Centro',
      ),
      Trip(
        id: 't2',
        routeId: 'r1',
        serviceId: serviceId,
        variantId: 'v1',
        headsign: 'Centro',
      ),
      Trip(
        id: 't3',
        routeId: 'r2',
        serviceId: serviceId,
        variantId: 'v2',
        headsign: 'Sur',
      ),
    ],
    times: const [
      StopTime(
        tripId: 't1',
        stopId: 's1',
        arrivalSeconds: 43800,
        departureSeconds: 43800,
        sequence: 1,
      ),
      StopTime(
        tripId: 't2',
        stopId: 's1',
        arrivalSeconds: 44400,
        departureSeconds: 44400,
        sequence: 1,
      ),
      StopTime(
        tripId: 't3',
        stopId: 's1',
        arrivalSeconds: 44100,
        departureSeconds: 44100,
        sequence: 1,
      ),
    ],
    calendars: [
      ServiceCalendar(
        serviceId: serviceId,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        weekdays: const {1, 2, 3, 4, 5, 6, 7},
      ),
    ],
  );
  repository.shapes['shape1'] = _shape;
  return repository;
}

BusPosition _bus({
  required int variantId,
  required double latitude,
  required double longitude,
  required DateTime receivedAt,
  double speedKmh = 0,
}) => BusPosition(
  sourceId: 'bus-$variantId',
  companyCode: 1,
  busCode: variantId,
  variantId: variantId,
  lineLabel: 'A',
  sublineDescription: 'A',
  destinationCode: 'N',
  destinationName: 'Centro',
  lineTypeCode: 1,
  lineTypeName: 'Regular',
  subsystemCode: 1,
  subsystemName: 'STM',
  latitude: latitude,
  longitude: longitude,
  speedKmh: speedKmh,
  receivedAt: receivedAt,
);
