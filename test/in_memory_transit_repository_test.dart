import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/data/gtfs_parser.dart';
import 'package:rumbo/features/stops_and_lines/data/in_memory_transit_repository.dart';
import 'package:rumbo/features/search/data/in_memory_transit_search_source.dart';
import 'package:rumbo/features/search/domain/query_normalizer.dart';

void main() {
  test(
    'compact GTFS repository searches stops and resolves their lines',
    () async {
      final bytes = File('assets/sample_gtfs/sample_gtfs.zip')
          .readAsBytesSync();
      final feed = parseGtfsZipCompact(bytes);
      final repository = InMemoryTransitRepository(feed);
      final firstStop = feed.stops.first;

      expect(feed.stopTimes, isEmpty);
      expect(
        repository.searchStops(firstStop.name),
        completion(contains(firstStop)),
      );
      expect(
        repository.nearbyStops(firstStop.latitude, firstStop.longitude, 50),
        completion(contains(firstStop)),
      );
      expect(repository.routesForStop(firstStop.id), completion(isNotEmpty));
      final schedule = await repository.scheduleForStops({firstStop.id});
      expect(schedule.trips, isNotEmpty);
      expect(schedule.stopTimes, isNotEmpty);
      final search = InMemoryTransitSearchSource(feed, repository);
      final matches = await search.searchStopsAndLines(
        const MontevideoQueryParser().parse(firstStop.name),
      );
      expect(matches.any((result) => result.stop?.id == firstStop.id), isTrue);
    },
  );
}
