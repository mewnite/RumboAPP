import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'gtfs_parser.dart';

class FeedDownload {
  const FeedDownload({
    required this.bytes,
    this.filePath,
    this.etag,
    this.lastModified,
    this.notModified = false,
  });
  final Uint8List bytes;
  final String? filePath;
  final String? etag, lastModified;
  final bool notModified;
}

Map<String, String> conditionalFeedHeaders({
  String? etag,
  String? lastModified,
}) {
  final headers = <String, String>{};
  if (etag != null) headers['If-None-Match'] = etag;
  if (lastModified != null) headers['If-Modified-Since'] = lastModified;
  return headers;
}

bool isFeedNotModified(int statusCode) => statusCode == 304;

abstract interface class TransitFeedSource {
  Future<FeedDownload> download({
    String? etag,
    String? lastModified,
    bool writeToFile = false,
  });
  Future<GtfsParseResult> parse(
    Uint8List bytes, {
    void Function(String stage, double progress)? onProgress,
    bool streamStopTimes = false,
  });
  Future<GtfsParseResult> parseFile(
    String zipPath, {
    void Function(String stage, double progress)? onProgress,
  });
}

class GtfsZipSource implements TransitFeedSource {
  GtfsZipSource(
    this.url, {
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();
  final String url;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<FeedDownload> download({
    String? etag,
    String? lastModified,
    bool writeToFile = false,
  }) async {
    if (url.isEmpty) {
      throw StateError(
        'La URL del feed no está configurada; se deben usar los datos de prueba incluidos.',
      );
    }
    final uri = Uri.tryParse(url);
    final isLocalDevelopmentHost =
        uri != null &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2' ||
            uri.host == '::1');
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' && isLocalDevelopmentHost))) {
      throw const FormatException(
        'La fuente GTFS debe ser HTTPS o HTTP en localhost para desarrollo.',
      );
    }
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      String? partialPath;
      try {
        final request = http.Request('GET', uri)
          ..headers['User-Agent'] = 'Rumbo/1.0 (app de transporte)'
          ..headers['Accept'] = 'application/zip';
        request.headers.addAll(
          conditionalFeedHeaders(etag: etag, lastModified: lastModified),
        );
        final response = await _client.send(request).timeout(timeout);
        if (isFeedNotModified(response.statusCode)) {
          return FeedDownload(
            bytes: Uint8List(0),
            etag: etag,
            lastModified: lastModified,
            notModified: true,
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'El servidor respondió HTTP ${response.statusCode}.',
          );
        }
        if (writeToFile) {
          partialPath =
              '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'rumbo-feed-${DateTime.now().microsecondsSinceEpoch}.zip';
          final sink = File(partialPath).openWrite();
          try {
            await response.stream.timeout(timeout).pipe(sink);
          } catch (_) {
            await sink.close();
            rethrow;
          }
          return FeedDownload(
            bytes: Uint8List(0),
            filePath: partialPath,
            etag: response.headers['etag'],
            lastModified: response.headers['last-modified'],
          );
        }
        final bytes = await response.stream.toBytes().timeout(timeout);
        return FeedDownload(
          bytes: Uint8List.fromList(bytes),
          etag: response.headers['etag'],
          lastModified: response.headers['last-modified'],
        );
      } catch (e) {
        lastError = e;
        if (partialPath != null) {
          final partial = File(partialPath);
          if (await partial.exists()) await partial.delete();
        }
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 300 * (1 << attempt)),
          );
        }
      }
    }
    throw TransitFeedNetworkException(
      'No se pudo descargar el feed GTFS luego de 3 intentos: $lastError',
    );
  }

  Future<GtfsParseResult> parseCompact(Uint8List bytes) async =>
      compute(parseGtfsZipCompact, bytes);

  @override
  Future<GtfsParseResult> parse(
    Uint8List bytes, {
    void Function(String, double)? onProgress,
    bool streamStopTimes = false,
  }) async {
    onProgress?.call('validando_zip', 0.05);
    onProgress?.call('procesando_archivos', 0.2);
    late final GtfsParseResult result;
    if (streamStopTimes) {
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'rumbo-stop-times-${DateTime.now().microsecondsSinceEpoch}.jsonl';
      try {
        result = await compute(parseGtfsZipToFile, {
          'bytes': bytes,
          'path': path,
        });
      } catch (_) {
        final output = File(path);
        if (await output.exists()) await output.delete();
        rethrow;
      }
    } else {
      result = await compute(parseGtfsZip, bytes);
    }
    onProgress?.call('datos_procesados', 1);
    return result;
  }

  @override
  Future<GtfsParseResult> parseFile(
    String zipPath, {
    void Function(String, double)? onProgress,
  }) async {
    onProgress?.call('validando_zip', 0.05);
    onProgress?.call('procesando_archivos', 0.2);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stopTimesPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'rumbo-stop-times-$stamp.csv';
    try {
      final result = await compute(parseGtfsZipFileToFile, {
        'zipPath': zipPath,
        'stopTimesPath': stopTimesPath,
      });
      final stopTimesCsv = File(stopTimesPath);
      if (await stopTimesCsv.exists()) await stopTimesCsv.delete();
      onProgress?.call('datos_procesados', 1);
      return result;
    } catch (_) {
      final stopTimesCsv = File(stopTimesPath);
      if (await stopTimesCsv.exists()) await stopTimesCsv.delete();
      rethrow;
    } finally {
      final zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();
    }
  }
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TransitFeedNetworkException implements Exception {
  const TransitFeedNetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}
