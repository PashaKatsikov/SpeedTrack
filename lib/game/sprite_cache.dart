import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Decodes and caches [ui.Image] instances for fast canvas drawing.
class SpriteCache {
  SpriteCache._();
  static final SpriteCache instance = SpriteCache._();

  final Map<String, ui.Image> _images = {};

  ui.Image? get(String assetPath) => _images[assetPath];

  bool get isLoaded => _images.isNotEmpty;

  /// Loads a list of asset paths. Safe to call multiple times; already
  /// decoded assets are skipped.
  Future<void> load(List<String> assetPaths) async {
    for (final path in assetPaths) {
      if (_images.containsKey(path)) continue;
      final image = await _decode(path);
      if (image != null) _images[path] = image;
    }
  }

  Future<ui.Image?> _decode(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
