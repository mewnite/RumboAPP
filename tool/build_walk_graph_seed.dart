import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:rumbo/features/trip_planner/domain/walk_graph.dart';

Map<String, String> _arguments(List<String> values) {
  final result = <String, String>{};
  for (final value in values) {
    final separator = value.indexOf('=');
    if (!value.startsWith('--') || separator < 3) {
      throw FormatException('Argumento inválido: $value');
    }
    result[value.substring(2, separator)] = value.substring(separator + 1);
  }
  return result;
}

Future<void> main(List<String> arguments) async {
  final options = _arguments(arguments);
  final inputPath = options['input'];
  final outputPath = options['output'];
  final metadataPath = options['metadata-output'];
  final sourceDate = options['source-date'];
  final sourceSha256 = options['source-sha256'];
  final sourceUrl = options['source-url'];
  final upstreamSha256 = options['upstream-sha256'];
  final upstreamUrl = options['upstream-url'];
  final sourceFileBytes = int.tryParse(options['source-bytes'] ?? '');
  final osmiumToolVersion = options['osmium-tool-version'];
  final bboxValues = options['bbox']?.split(',');
  if (inputPath == null ||
      outputPath == null ||
      metadataPath == null ||
      sourceDate == null ||
      sourceSha256 == null ||
      sourceUrl == null ||
      upstreamSha256 == null ||
      upstreamUrl == null ||
      sourceFileBytes == null ||
      osmiumToolVersion == null ||
      bboxValues == null ||
      bboxValues.length != 4) {
    stderr.writeln('Faltan argumentos requeridos para build_walk_graph_seed.');
    exitCode = 2;
    return;
  }

  final input = File(inputPath);
  final normalizedBytes = await input.readAsBytes();
  final decodeWatch = Stopwatch()..start();
  final decoded = jsonDecode(utf8.decode(normalizedBytes));
  decodeWatch.stop();
  stdout.writeln(
    '[performance] walk_seed_json_decode=${decodeWatch.elapsedMilliseconds}ms '
    'bytes=${normalizedBytes.length}',
  );
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('El JSON normalizado debe ser un objeto.');
    exitCode = 1;
    return;
  }

  final buildWatch = Stopwatch()..start();
  final graph = WalkGraph.fromGeoJson(
    decoded,
    sourceDate: sourceDate,
    sourceSha256: sourceSha256,
  );
  buildWatch.stop();
  if (graph == null || graph.edgeCount == 0) {
    stderr.writeln('No se generó una red peatonal utilizable.');
    exitCode = 1;
    return;
  }

  final encodeWatch = Stopwatch()..start();
  final bytes = graph.toSeedBytes();
  encodeWatch.stop();
  final output = File(outputPath)..parent.createSync(recursive: true);
  await output.writeAsBytes(bytes, flush: true);
  final bounds = graph.boundsMicrodegrees;
  final metadata = <String, Object>{
    'format': 'RWB1',
    'format_version': 1,
    'source': 'Geofabrik Uruguay extract',
    'source_url': sourceUrl,
    'source_date': sourceDate,
    'source_bytes': sourceFileBytes,
    'source_sha256': sourceSha256,
    'upstream_source_url': upstreamUrl,
    'upstream_source_sha256': upstreamSha256,
    'osmium_tool_version': osmiumToolVersion,
    'bbox': {
      'west': double.parse(bboxValues[0]),
      'south': double.parse(bboxValues[1]),
      'east': double.parse(bboxValues[2]),
      'north': double.parse(bboxValues[3]),
    },
    'graph_bounds': {
      'south': bounds[0] / 1000000,
      'west': bounds[1] / 1000000,
      'north': bounds[2] / 1000000,
      'east': bounds[3] / 1000000,
    },
    'exported_way_count': int.parse(options['exported-way-count'] ?? '0'),
    'clipped_way_count': int.parse(options['clipped-way-count'] ?? '0'),
    'included_way_count': graph.wayCount,
    'vertex_count': graph.vertexCount,
    'edge_count': graph.edgeCount,
    'geometry_point_count': graph.geometryPointCount,
    'seed_bytes': bytes.length,
    'seed_sha256': sha256.convert(bytes).toString(),
  };
  final metadataFile = File(metadataPath)..parent.createSync(recursive: true);
  await metadataFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(metadata),
    flush: true,
  );
  stdout.writeln(
    '[performance] walk_seed_graph_build=${buildWatch.elapsedMilliseconds}ms '
    'encode=${encodeWatch.elapsedMilliseconds}ms',
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(metadata));
}
