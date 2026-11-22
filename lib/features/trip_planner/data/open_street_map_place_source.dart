import 'package:http/http.dart' as http;

import '../../search/data/remote_geocoding_source.dart';
import '../../search/domain/query_normalizer.dart';
import '../domain/trip_planner.dart';

/// Trip-planner adapter for the shared geocoder and its address precision rules.
class OpenStreetMapPlaceSource {
  OpenStreetMapPlaceSource({required String endpoint, http.Client? client})
    : _source = RemoteGeocodingSource(endpoint: endpoint, client: client);

  final RemoteGeocodingSource _source;
  final MontevideoQueryParser _queryParser = const MontevideoQueryParser();

  void close() => _source.close();

  Future<List<TripEndpoint>> search(String query) async {
    final parsedQuery = _queryParser.parse(query);
    final results = await _source.searchRemote(parsedQuery, limit: 5);
    return List<TripEndpoint>.unmodifiable(
      results.map((result) => result.toTripEndpoint()),
    );
  }
}
