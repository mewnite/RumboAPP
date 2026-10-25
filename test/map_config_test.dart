import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('map_config.dart is the only Dart source of tile and style URLs', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final mapTileUrl = RegExp(r'https?://tiles\.openfreemap\.org/');
    final urlSources = dartFiles
        .where((file) => mapTileUrl.hasMatch(file.readAsStringSync()))
        .map((file) => file.uri.pathSegments.join('/'))
        .toList();

    expect(urlSources, ['lib/core/config/map_config.dart']);
  });
}
