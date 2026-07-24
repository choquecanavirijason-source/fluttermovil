import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

/// Captura la foto final del asistente de trabajo / recomendación IA:
/// overlay Flutter (pestañas + líneas de medición) + foto real de la cámara
/// frontal, compuestas y recortadas a la franja de ojos. Concentra toda la
/// dependencia de los paquetes `image` y `camera` fuera de la página.
class EyeTrackingPhotoPipeline {
  final GlobalKey previewCaptureKey;

  const EyeTrackingPhotoPipeline({required this.previewCaptureKey});

  /// Captura el overlay Flutter (pestañas PNG) mientras MediaPipe sigue
  /// activo. Las áreas de cámara nativa quedan transparentes en el PNG
  /// resultante.
  Future<Uint8List?> captureOverlay(BuildContext context) async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!context.mounted) return null;
    final boundary =
        previewCaptureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || !boundary.attached) return null;
    try {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final ratio = dpr < 2.0 ? 2.0 : dpr;
      final image = await boundary.toImage(pixelRatio: ratio);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bd?.buffer.asUint8List();
    } catch (e) {
      debugPrint('captureOverlay: $e');
      return null;
    }
  }

  /// Abre la cámara Flutter brevemente, toma foto de la cara y la compone
  /// con el overlay de pestañas. Devuelve la región de ojos recortada.
  Future<Uint8List?> captureAndComposite(
    BuildContext context,
    Uint8List? overlayBytes,
  ) async {
    CameraController? ctrl;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted || !context.mounted) return overlayBytes;

      final cameras = await availableCameras();
      if (cameras.isEmpty || !context.mounted) return overlayBytes;

      final target = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      ctrl = CameraController(
        target,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await ctrl.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final xfile = await ctrl.takePicture();
      final faceBytes = await File(xfile.path).readAsBytes();

      return compositeAndCrop(faceBytes, overlayBytes);
    } catch (e) {
      debugPrint('captureAndComposite: $e');
      return overlayBytes;
    } finally {
      await ctrl?.dispose();
    }
  }

  /// Compone la foto de cara con el overlay de pestañas (alpha blend) y
  /// recorta la zona de ojos (franja central y=22%–64%).
  static Uint8List compositeAndCrop(
    Uint8List faceRaw,
    Uint8List? overlayRaw,
  ) {
    var faceImg = img.decodeImage(faceRaw);
    if (faceImg == null) return faceRaw;

    // Aplica la rotación EXIF (la foto suele guardarse apaisada + tag de giro).
    faceImg = img.bakeOrientation(faceImg);

    // La cámara frontal guarda la foto sin espejo; la invertimos para que
    // coincida con el overlay que se renderizó sobre el preview espejado.
    var canvas = img.flipHorizontal(faceImg);

    if (overlayRaw != null) {
      final overlayImg = img.decodeImage(overlayRaw);
      if (overlayImg != null) {
        // El preview usa BoxFit.cover: la pantalla solo muestra un recorte
        // centrado de la foto. Recortamos la foto a la proporción del overlay
        // (pantalla) ANTES de componer; si no, las pestañas quedan corridas.
        final overlayAspect = overlayImg.width / overlayImg.height;
        final faceAspect = canvas.width / canvas.height;
        int cw = canvas.width, ch = canvas.height, cx = 0, cy = 0;
        if (faceAspect > overlayAspect) {
          // Foto más ancha que la pantalla: recorta los lados.
          cw = (canvas.height * overlayAspect).round();
          cx = ((canvas.width - cw) / 2).round();
        } else if (faceAspect < overlayAspect) {
          // Foto más alta que la pantalla: recorta arriba/abajo.
          ch = (canvas.width / overlayAspect).round();
          cy = ((canvas.height - ch) / 2).round();
        }
        canvas = img.copyCrop(canvas, x: cx, y: cy, width: cw, height: ch);

        // Ahora ambas tienen la misma proporción: escala 1:1 sin deformar.
        final overlayScaled = img.copyResize(
          overlayImg,
          width: canvas.width,
          height: canvas.height,
          interpolation: img.Interpolation.linear,
        );
        img.compositeImage(canvas, overlayScaled, blend: img.BlendMode.alpha);
      }
    }

    // Recorta la zona de los ojos.
    final y = (canvas.height * 0.22).round();
    final h = (canvas.height * 0.42).round();
    final cropped = img.copyCrop(
      canvas,
      x: 0,
      y: y,
      width: canvas.width,
      height: h,
    );
    final rotated = img.copyRotate(cropped, angle: 180);
    return Uint8List.fromList(img.encodePng(rotated));
  }
}
