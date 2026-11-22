import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tool/build_walk_graph_seed.dart' as seed_builder;

void main() {
  test('seed manifest is valid JSON and ends with a newline', () {
    final encoded = seed_builder.encodeSeedManifest({
      'format': 'RWB1',
      'seed_bytes': 123,
    });

    expect(encoded, endsWith('\n'));
    expect(jsonDecode(encoded), {'format': 'RWB1', 'seed_bytes': 123});
  });
}
