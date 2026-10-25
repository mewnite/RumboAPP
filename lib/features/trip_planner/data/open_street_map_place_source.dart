import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/trip_planner.dart';

class OpenStreetMapPlaceSource {
  OpenStreetMapPlaceSource({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final String endpoint;
  final http.Client _client;
  final Map<String, List<TripEndpoint>> _cache = {};

  void close() => _client.close();

  Future<List<TripEndpoint>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 3 || normalized.length > 160) {
      throw ArgumentError('La búsqueda debe tener entre 3 y 160 caracteres.');
    }
    final cacheKey = normalized.toLowerCase();
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final baseUri = Uri.tryParse(endpoint);
    final localDevelopmentHost =
        baseUri != null &&
        (baseUri.host == 'localhost' ||
            baseUri.host == '127.0.0.1' ||
            baseUri.host == '10.0.2.2' ||
            baseUri.host == '::1');
    if (baseUri == null ||
        !baseUri.hasAuthority ||
        (baseUri.scheme != 'https' &&
            !(baseUri.scheme == 'http' && localDevelopmentHost))) {
      throw const FormatException(
        'La URL de búsqueda de lugares no es válida.',
      );
    }

    final uri = baseUri.replace(
      queryParameters: {
        'q': normalized,
        'countrycodes': 'uy',
        'format': 'jsonv2',
        'limit': '5',
      },
    );
    final response = await _client
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'El servicio de lugares respondió HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException(
        'La respuesta del servicio de lugares no es una lista.',
      );
    }
    final results = <TripEndpoint>[];
    for (final value in decoded) {
      if (value is! Map<String, dynamic>) continue;
      final latitude = double.tryParse(value['lat']?.toString() ?? '');
      final longitude = double.tryParse(value['lon']?.toString() ?? '');
      final name = value['display_name'];
      if (latitude == null ||
          longitude == null ||
          name is! String ||
          name.trim().isEmpty ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -35.2 ||
          latitude > -30.0 ||
          longitude < -58.5 ||
          longitude > -53.0) {
        continue;
      }
      results.add(
        TripEndpoint(name: name, latitude: latitude, longitude: longitude),
      );
    }
    final immutableResults = List<TripEndpoint>.unmodifiable(results);
    _cache[cacheKey] = immutableResults;
    return immutableResults;
  }
}
