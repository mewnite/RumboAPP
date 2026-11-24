import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';
import 'stm_online_geojson_parser.dart';

class MontevideoRealtimeBusSource implements RealtimeBusSource {
  MontevideoRealtimeBusSource(
    this.apiBaseUrl, {
    http.Client? client,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final String apiBaseUrl;
  final http.Client _client;
  final DateTime Function() _clock;

  void close() => _client.close();

  @override
  Future<RealtimeSnapshot> fetch({Set<String>? lines}) async {
    final baseUri = Uri.tryParse(apiBaseUrl);
    final isLocalDevelopmentHost =
        baseUri != null &&
        (baseUri.host == 'localhost' ||
            baseUri.host == '127.0.0.1' ||
            baseUri.host == '10.0.2.2' ||
            baseUri.host == '::1');
    if (baseUri == null ||
        !baseUri.hasAuthority ||
        (baseUri.scheme != 'https' &&
            !(baseUri.scheme == 'http' && isLocalDevelopmentHost))) {
      throw const FormatException(
        'La URL de la API de tiempo real no es válida.',
      );
    }
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final queryParams = <String, String>{'format': 'geojson'};
    if (lines != null && lines.isNotEmpty) {
      queryParams['lines'] = lines.join(',');
    }
    final uri = baseUri.replace(
      path: '$basePath/buses',
      queryParameters: queryParams,
    );
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/geo+json'})
        .timeout(const Duration(seconds: 25));
    stopwatch.stop();
    developer.log(
      '[performance] api_buses_ms=${stopwatch.elapsedMilliseconds} '
      'bytes=${response.body.length}',
      name: 'Rumbo',
    );
    if (response.statusCode == 429) {
      developer.log(
        '[performance] api_buses_429 uri=$uri '
        'retry_after=${response.headers['retry-after']}',
        name: 'Rumbo',
      );
      throw RealtimeBusRateLimitedException(
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      developer.log(
        '[performance] api_buses_error uri=$uri status=${response.statusCode} '
        'body=${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
        name: 'Rumbo',
      );
      throw HttpException(
        'La API de tiempo real respondió HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    return parseStmOnlineGeoJson(response.body, _clock());
  }

  static Duration? _retryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }
}
