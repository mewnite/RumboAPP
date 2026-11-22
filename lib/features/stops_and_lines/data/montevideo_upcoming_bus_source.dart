import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/transit_repository.dart';

class MontevideoUpcomingBusSource implements OfficialUpcomingBusArrivalsSource {
  MontevideoUpcomingBusSource(
    this.apiBaseUrl, {
    http.Client? client,
    this._requestTimeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final String apiBaseUrl;
  final http.Client _client;
  final Duration _requestTimeout;

  @override
  void close() => _client.close();

  @override
  Future<List<OfficialBusArrival>> upcomingForStop({
    required String stopId,
    required Set<String> lines,
    int amountPerLine = 1,
  }) async {
    if (!RegExp(r'^\d+$').hasMatch(stopId)) {
      throw ArgumentError.value(stopId, 'stopId', 'Debe ser numérico.');
    }
    if (lines.isEmpty ||
        lines.any(
          (line) =>
              line.trim().isEmpty ||
              !RegExp(r'^[A-Za-z0-9 ,-]+$').hasMatch(line),
        )) {
      throw ArgumentError.value(lines, 'lines', 'Filtro de líneas inválido.');
    }
    if (amountPerLine < 1 || amountPerLine > 5) {
      throw ArgumentError.value(
        amountPerLine,
        'amountPerLine',
        'Debe estar entre 1 y 5.',
      );
    }

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
    final uri = baseUri.replace(
      path: '$basePath/busstops/$stopId/upcomingbuses',
      queryParameters: {
        'lines': (lines.toList()..sort()).join(','),
        'amountperline': '$amountPerLine',
      },
    );
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'La API de arribos respondió HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<Object?>) {
      throw const FormatException(
        'La respuesta de arribos no es una lista JSON.',
      );
    }
    return decoded.map(_parseArrival).toList(growable: false);
  }

  OfficialBusArrival _parseArrival(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Arribo STM inválido.');
    }
    final busId = _integer(value['busId'], 'busId');
    final lineVariantId = _integer(value['lineVariantId'], 'lineVariantId');
    final line = value['line'];
    if (line is! String || line.trim().isEmpty) {
      throw const FormatException('Arribo STM sin línea.');
    }
    final etaSeconds = _integer(value['eta'], 'eta');
    if (etaSeconds < 0) {
      throw const FormatException('El ETA STM no puede ser negativo.');
    }
    final location = _parseLocation(value['location']);
    final destination = value['destination'];

    return OfficialBusArrival(
      busId: busId,
      lineVariantId: lineVariantId,
      line: line,
      etaSeconds: etaSeconds,
      destination: destination is String ? destination : '',
      latitude: location?.$1,
      longitude: location?.$2,
    );
  }

  (double, double)? _parseLocation(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?> ||
        value['type'] != 'Point' ||
        value['coordinates'] is! List<Object?>) {
      throw const FormatException('Ubicación del arribo STM inválida.');
    }
    final coordinates = value['coordinates']! as List<Object?>;
    if (coordinates.length != 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      throw const FormatException('Coordenadas del arribo STM inválidas.');
    }
    final longitude = (coordinates[0]! as num).toDouble();
    final latitude = (coordinates[1]! as num).toDouble();
    if (!longitude.isFinite ||
        !latitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        latitude < -90 ||
        latitude > 90) {
      throw const FormatException('Coordenadas del arribo STM fuera de rango.');
    }
    return (latitude, longitude);
  }

  int _integer(Object? value, String field) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.truncateToDouble()) {
      throw FormatException('Campo STM "$field" inválido.');
    }
    return value.toInt();
  }
}
