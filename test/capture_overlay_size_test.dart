import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:Probador/eye_tracking_photo_pipeline.dart';

/// Foto sintética con detalle (degradados + bandas) para que cualquier
/// diferencia de recorte, escala o mezcla se note en los bytes del JPEG.
Uint8List syntheticPhoto(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 255) ~/ w,
        (y * 255) ~/ h,
        ((x ~/ 7 + y ~/ 5) % 2) * 200,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Overlay transparente, como el que salía de `captureOverlay` con el
/// painter de debug apagado y las pestañas 3D ocultas.
Uint8List transparentOverlay(int w, int h) => Uint8List.fromList(
  img.encodePng(img.Image(width: w, height: h, numChannels: 4)),
);

void main() {
  group('Foto sin capturar el overlay vacío', () {
    final photo = syntheticPhoto(540, 720);

    // Overlay más grande que la franja de la foto (se agranda la foto) y
    // más chico (se achica el overlay): los dos caminos de la composición.
    for (final size in [
      (width: 823, height: 1781),
      (width: 300, height: 650),
    ]) {
      for (final mirror in [false, true]) {
        for (final flip in [false, true]) {
          for (final rotate in [false, true]) {
            test('idéntica byte a byte: overlay ${size.width}x${size.height} '
                'espejo=$mirror echada=$flip girada=$rotate', () {
              final before = EyeTrackingPhotoPipeline.compositeAndCrop(
                photo,
                transparentOverlay(size.width, size.height),
                mirror: mirror,
                flipEyeBand: flip,
                rotate180: rotate,
              );
              final after = EyeTrackingPhotoPipeline.compositeAndCrop(
                photo,
                null,
                mirror: mirror,
                flipEyeBand: flip,
                rotate180: rotate,
                overlaySize: size,
              );
              expect(after, orderedEquals(before));
            });
          }
        }
      }
    }
  });

  testWidgets('las medidas calculadas coinciden con la captura real', (
    tester,
  ) async {
    // Tamaño con decimales, como el de un teléfono real.
    const logical = Size(411.43, 890.29);
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.fromSize(size: logical),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
    final expected = EyeTrackingPhotoPipeline.overlayPixelSize(boundary.size);
    expect(image!.width, expected.width);
    expect(image.height, expected.height);
    image.dispose();
  });
}
