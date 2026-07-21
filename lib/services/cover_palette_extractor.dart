import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Converts an imported cover into the three colors used by the carousel.
///
/// EPUB/PDF importers can pass their embedded cover bytes here before creating
/// a [Book]. The image is decoded at thumbnail size to keep this work cheap.
abstract final class CoverPaletteExtractor {
  static Future<Uint8List> normalize(
    Uint8List bytes, {
    int targetWidth = 1200,
  }) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      return bytes;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Future<List<Color>> fromBytes(
    Uint8List bytes, {
    required String fallbackSeed,
  }) async {
    if (bytes.isEmpty) return fromText(fallbackSeed);

    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 36,
        targetHeight: 54,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return fromText(fallbackSeed);

      var red = 0;
      var green = 0;
      var blue = 0;
      var samples = 0;
      final pixels = data.buffer.asUint8List();
      for (var i = 0; i + 3 < pixels.length; i += 16) {
        final alpha = pixels[i + 3];
        if (alpha < 180) continue;
        final brightness = pixels[i] + pixels[i + 1] + pixels[i + 2];
        if (brightness < 75 || brightness > 735) continue;
        red += pixels[i];
        green += pixels[i + 1];
        blue += pixels[i + 2];
        samples++;
      }
      if (samples == 0) return fromText(fallbackSeed);

      final average = Color.fromARGB(
        255,
        red ~/ samples,
        green ~/ samples,
        blue ~/ samples,
      );
      return _paletteFromColor(average);
    } catch (_) {
      return fromText(fallbackSeed);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static List<Color> fromText(String text) {
    var hash = 17;
    for (final unit in text.codeUnits) {
      hash = (hash * 37 + unit) & 0x7FFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    return _paletteFromColor(HSVColor.fromAHSV(1, hue, .38, .72).toColor());
  }

  static List<Color> _paletteFromColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    final primary = hsv
        .withSaturation(hsv.saturation.clamp(.28, .62))
        .withValue(hsv.value.clamp(.58, .8))
        .toColor();
    final surface = hsv
        .withSaturation((hsv.saturation * .28).clamp(.08, .2))
        .withValue(.95)
        .toColor();
    final ink = hsv
        .withSaturation(hsv.saturation.clamp(.24, .58))
        .withValue(.36)
        .toColor();
    return [primary, surface, ink];
  }
}
