import 'dart:convert';

import '../../../core/config/transit_config.dart';
import '../domain/transit_models.dart';

class UruguayBounds {
  const UruguayBounds({
    this.minimumLatitude = -35.2,
    this.maximumLatitude = -30.0,
    this.minimumLongitude = -58.5,
    this.maximumLongitude = -53.0,
  });
  final double minimumLatitude,
      maximumLatitude,
      minimumLongitude,
      maximumLongitude;
}

RealtimeSnapshot parseStmOnlineGeoJson(
  String json,
  DateTime receivedAt, {
  UruguayBounds bounds = const UruguayBounds(
    minimumLatitude: transitMinimumLatitude,
    maximumLatitude: transitMaximumLatitude,
    minimumLongitude: transitMinimumLongitude,
    maximumLongitude: transitMaximumLongitude,
  ),
}) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic> ||
      decoded['type'] != 'FeatureCollection' ||
      decoded['features'] is! List) {
    throw const FormatException(
      'GeoJSON STM inválido: se esperaba FeatureCollection.',
    );
  }

  final reasons = <String, int>{};
  var discarded = 0;
  var duplicates = 0;
  final positionsById = <String, BusPosition>{};
  void discard(String reason) {
    discarded++;
    reasons.update(reason, (count) => count + 1, ifAbsent: () => 1);
  }

  int? intValue(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? stringValue(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  for (final rawFeature in decoded['features'] as List) {
    if (rawFeature is! Map<String, dynamic>) {
      discard('feature_malformada');
      continue;
    }
    final geometry = rawFeature['geometry'];
    if (geometry is! Map<String, dynamic> ||
        geometry['type'] != 'Point' ||
        geometry['coordinates'] is! List) {
      discard('geometria_ausente_o_invalida');
      continue;
    }
    final coordinates = geometry['coordinates'] as List;
    if (coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      discard('coordenadas_invalidas');
      continue;
    }
    final longitude = (coordinates[0] as num).toDouble();
    final latitude = (coordinates[1] as num).toDouble();
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      discard('coordenadas_fuera_de_rango');
      continue;
    }
    if (latitude < bounds.minimumLatitude ||
        latitude > bounds.maximumLatitude ||
        longitude < bounds.minimumLongitude ||
        longitude > bounds.maximumLongitude) {
      discard('fuera_de_uruguay');
      continue;
    }
    final properties = rawFeature['properties'];
    if (properties is! Map<String, dynamic>) {
      discard('propiedades_ausentes');
      continue;
    }
    final id = properties['id'];
    final company = intValue(properties['codigoEmpresa']);
    final bus = intValue(properties['codigoBus']);
    final variant = intValue(properties['variante']);
    final destinationCode = stringValue(properties['destino']);
    final lineType = intValue(properties['tipoLinea']);
    final subsystem = intValue(properties['subsistema']);
    final speedValue = properties['velocidad'];
    final speed = speedValue is num
        ? speedValue.toDouble()
        : double.tryParse(speedValue?.toString() ?? '');
    final line = stringValue(properties['linea']);
    final subline = stringValue(properties['sublinea']);
    final destination = stringValue(properties['destinoDesc']);
    final lineTypeName = stringValue(properties['tipoLineaDesc']);
    final subsystemName = stringValue(properties['subsistemaDesc']);
    if (id == null ||
        company == null ||
        bus == null ||
        variant == null ||
        destinationCode == null ||
        lineType == null ||
        subsystem == null ||
        speed == null ||
        !speed.isFinite ||
        line == null ||
        subline == null ||
        destination == null ||
        lineTypeName == null ||
        subsystemName == null) {
      discard('campos_obligatorios_ausentes_o_invalidos');
      continue;
    }
    final key = '${id.runtimeType}:$id';
    if (positionsById.containsKey(key)) {
      duplicates++;
      discard('id_duplicado');
    }
    positionsById[key] = BusPosition(
      sourceId: id,
      companyCode: company,
      busCode: bus,
      variantId: variant,
      lineLabel: line,
      sublineDescription: subline,
      destinationCode: destinationCode,
      destinationName: destination,
      lineTypeCode: lineType,
      lineTypeName: lineTypeName,
      subsystemCode: subsystem,
      subsystemName: subsystemName,
      latitude: latitude,
      longitude: longitude,
      speedKmh: speed,
      receivedAt: receivedAt,
      rawExtras: <String, Object?>{
        if (properties.containsKey('frecuencia'))
          'frecuencia': properties['frecuencia'],
        if (properties.containsKey('version')) 'version': properties['version'],
      },
    );
  }
  return RealtimeSnapshot(
    positions: positionsById.values.toList(growable: false),
    discardedCount: discarded,
    duplicateCount: duplicates,
    discardReasons: reasons,
  );
}
