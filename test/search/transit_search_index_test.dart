import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/search/data/transit_search_index.dart';
import 'package:rumbo/features/search/domain/query_normalizer.dart';
import 'package:rumbo/features/search/domain/search_models.dart';

void main() {
  test('includes saved places in local search results', () async {
    const parser = MontevideoQueryParser();
    final index = await TransitSearchIndex.fromFeed(null);
    const savedPlace = SearchResult(
      id: 'favorite:place-home',
      kind: SearchEntityKind.favorite,
      title: 'Casa',
      subtitle: 'Lugar guardado',
      latitude: -34.9,
      longitude: -56.19,
      precision: GeoPrecision.approximateArea,
      source: SearchDataSource.userStorage,
    );

    final results = index.search(
      parser.parse('casa'),
      additionalResults: const [savedPlace],
    );

    expect(results, [savedPlace]);
  });

  test('repeated local searches reuse a bounded result cache', () async {
    const parser = MontevideoQueryParser();
    final index = await TransitSearchIndex.fromFeed(null);
    final first = index.search(parser.parse('pocitos'));
    final stopwatch = Stopwatch()..start();
    final second = index.search(parser.parse('pocitos'));
    stopwatch.stop();

    expect(first, second);
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
  });
}
