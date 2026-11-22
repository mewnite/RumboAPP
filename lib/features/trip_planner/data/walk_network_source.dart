import "dart:convert";
import "dart:io";

import "package:http/http.dart" as http;
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

import "../domain/walk_graph.dart";

/// Source de la red peatonal real: descarga de la endpoint del proxy
/// (`/osm/pedestrian`, Overpass) + persistencia local (última red válida).
class WalkNetworkSource {
  WalkNetworkSource({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final String endpoint;
  final http.Client _client;

  static const String _cacheFileName = "rumbo_walk_network.json";

  void close() => _client.close();

  /// Descarga la red de la endpoint (Overpass via proxy).
  Future<Map<String, dynamic>?> fetch() async {
    if (endpoint.isEmpty) return null;
    try {
      final response = await _client.get(Uri.parse(endpoint));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } on Exception {
      // Fallback: conservar la última red válida (caché o sin red).
      return null;
    }
  }

  /// Devuelve el directorio de documentos. En entornos sin la plataforma
  /// (ej. tests) la llamada nunca completa, así que la carregan con un
  /// timeout corto y devuelven null — no hay caché sin directorio.
  static Future<Directory?> _documentsDirectory() async {
    try {
      return await Future.any<Directory?>([
        getApplicationDocumentsDirectory(),
        Future<Directory?>.delayed(const Duration(milliseconds: 250)),
      ]);
    } on Exception {
      return null;
    }
  }

  /// JSON cacheado localmente (última red válida), null si no existe.
  Future<Map<String, dynamic>?> readCached() async {
    final dir = await _documentsDirectory();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, _cacheFileName));
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Corrupto — se trata como "no hay caché" (se vuelve a descargar).
    }
    return null;
  }

  /// Guarda la red en el directorio de documentos (temp + rename).
  Future<void> writeCached(Map<String, dynamic> json) async {
    try {
      final dir = await _documentsDirectory();
      if (dir == null) return;
      final target = File(p.join(dir.path, _cacheFileName));
      final temp = File("${target.path}.new");
      await temp.writeAsString(jsonEncode(json), flush: true);
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    } on Exception {
      // No se puede cachear — ignora.
    }
  }

  static WalkGraph? buildGraph(Map<String, dynamic> data) =>
      WalkGraph.fromGeoJson(data);
}
