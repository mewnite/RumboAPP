import 'dart:developer' as developer;

import 'package:flutter/services.dart';

class WalkGraphSeedSource {
  WalkGraphSeedSource({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetPath = 'assets/walk_graph/walk_graph_seed.bin';
  final AssetBundle _bundle;

  Future<Uint8List> loadSeedBytes() async {
    final asset = await _bundle.load(assetPath);
    final seedBytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    developer.log(
      '[performance] walk_seed_asset_loaded=${seedBytes.length}bytes',
      name: 'Rumbo',
    );
    return seedBytes;
  }
}
