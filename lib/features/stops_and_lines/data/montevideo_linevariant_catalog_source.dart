import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'stm_linevariant_catalog.dart';

class MontevideoLineVariantCatalogSource {
  MontevideoLineVariantCatalogSource(this.apiBaseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String apiBaseUrl;
  final http.Client _client;

  void close() => _client.close();

  Future<StmLineVariantCatalog> fetch() async {
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
      throw const FormatException('La URL del catálogo STM no es válida.');
    }
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final uri = baseUri.replace(path: '$basePath/linevariants');
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'El catálogo de variantes STM respondió HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    return StmLineVariantCatalog.fromJson(jsonDecode(response.body));
  }
}
