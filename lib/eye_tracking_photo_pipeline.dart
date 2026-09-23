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
      // El overlay lleva el MAPEO, que es la guía que después mira la
      // operaria: a resolución lógica (1.0) los números y las líneas salían
      // pixelados. 2.0 los deja nítidos a la resolución de la foto real.
      //
      // No subir más de esto a la ligera: este PNG se decodifica COMPLETO
      // otra vez en `compositeAndCrop`, y con el devicePixelRatio del
      // equipo (~3x en Samsung) daba una imagen sin comprimir de ~90 MB.
      // Ese pico, con Filament y MediaPipe todavía cargados, fue la causa
      // confirmada de que el sistema matara el proceso por falta de memoria
      // (logcat: lmkd "min2x watermark is breached even after kill").
      const ratio = 2.0;
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
  ///
  /// [preferFrontCamera] debe coincidir con la cámara que estaba usando el
  /// tracking en vivo (ver `_usingFrontCamera` en `eye_tracking_page.dart`,
  /// sincronizado con el botón de cambiar cámara) — el caso de uso real es
  /// la OPERARIA apuntando la cámara a la CLIENTA (no una selfie), así que
  /// no se puede asumir frontal siempre.
  Future<Uint8List?> captureAndComposite(
    BuildContext context,
    Uint8List? overlayBytes, {
    bool preferFrontCamera = true,
  }) async {
    CameraController? ctrl;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted || !context.mounted) return overlayBytes;

      final cameras = await availableCameras();
      if (cameras.isEmpty || !context.mounted) return overlayBytes;

      final desiredDirection = preferFrontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final target = cameras.firstWhere(
        (c) => c.lensDirection == desiredDirection,
        orElse: () => cameras.first,
      );

      // NO cambiar a `high`/`veryHigh` buscando más nitidez: esos presets
      // entregan 16:9, que en Android es un recorte del sensor 4:3 y pierde
      // campo VERTICAL. Con el recorte a la franja de los ojos que viene
      // después, eso se traduce en una foto mucho más cerrada — probado en
      // dispositivo: la guía quedaba tan encima que las líneas del mapeo
      // llegaban hasta las cejas. `medium` mantiene el encuadre correcto.
      //
      // Para que el MAPEO se vea nítido no hace falta subir esto: lo que
      // importa es la resolución con que se captura el overlay (ver
      // `captureOverlay`), que se compone encima.
      ctrl = CameraController(
        target,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await ctrl.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final xfile = await ctrl.takePicture();
      final faceBytes = await File(xfile.path).readAsBytes();

      return compositeAndCrop(
        faceBytes,
        overlayBytes,
        mirror: preferFrontCamera,
      );
    } catch (e) {
      debugPrint('captureAndComposite: $e');
      return overlayBytes;
    } finally {
      await ctrl?.dispose();
    }
  }

  /// Compone la foto de cara con el overlay de pestañas (alpha blend) y
  /// recorta la zona de ojos (franja central y=22%–64%).
  ///
  /// [mirror] debe ser `true` solo para cámara FRONTAL: el preview en
  /// pantalla se muestra espejado por convención selfie, así que el overlay
  /// (pestañas + líneas de medición) se renderizó en ese espacio espejado
  /// y hay que espejar también la foto real (que se guarda sin espejo) para
  /// que ambos coincidan. La cámara TRASERA no espeja su preview — con
  /// `mirror: true` ahí la foto quedaría invertida izquierda/derecha contra
  /// un overlay que nunca estuvo espejado.
  static Uint8List compositeAndCrop(
    Uint8List faceRaw,
    Uint8List? overlayRaw, {
    bool mirror = true,
  }) {
    var faceImg = img.decodeImage(faceRaw);
    if (faceImg == null) return faceRaw;

    // Aplica la rotación EXIF (la foto suele guardarse apaisada + tag de giro).
    faceImg = img.bakeOrientation(faceImg);

    var canvas = mirror ? img.flipHorizontal(faceImg) : faceImg;

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

        // Se RECORTA la franja de los ojos en las dos imágenes ANTES de
        // escalar y componer. Antes se escalaba la foto entera a la
        // resolución del overlay y recién después se recortaba: se gastaba
        // memoria en píxeles que se iban a tirar, y ese pico (con Filament
        // y MediaPipe cargados) dejaba al proceso al borde — en logcat se
        // veían objetos grandes de 16-27 MB, GC constante y frames de 3 s.
        canvas = _cropEyeBand(canvas);
        final overlayBand = _cropEyeBand(overlayImg);

        // Se compone a la resolución del OVERLAY y no a la de la foto: el
        // mapeo son líneas finas y números, y encogerlos a ~480p (lo que
        // mide la foto) era lo que los dejaba pixelados. Escalando la foto
        // hacia arriba, el mapeo entra 1:1 y queda limpio.
        if (overlayBand.width > canvas.width) {
          canvas = img.copyResize(
            canvas,
            width: overlayBand.width,
            height: overlayBand.height,
            interpolation: img.Interpolation.cubic,
          );
          img.compositeImage(canvas, overlayBand, blend: img.BlendMode.alpha);
        } else {
          final overlayScaled = img.copyResize(
            overlayBand,
            width: canvas.width,
            height: canvas.height,
            interpolation: img.Interpolation.linear,
          );
          img.compositeImage(canvas, overlayScaled, blend: img.BlendMode.alpha);
        }
        return Uint8List.fromList(img.encodePng(canvas));
      }
    }

    final cropped = _cropEyeBand(canvas);
    // Sin girar 180° al final. Antes se enderezaba la foto, pero esta
    // imagen es la GUÍA que la operaria mira mientras trabaja: tiene que
    // quedar en la misma orientación en que ve a la clienta, que está
    // acostada. Enderezarla obligaba a traducir mentalmente izquierda y
    // derecha contra lo que tiene delante.
    return Uint8List.fromList(img.encodePng(cropped));
  }

  /// Franja de los ojos: y=22%–64% del alto, a todo lo ancho.
  ///
  /// Se probó derivar el recorte de los landmarks para que siguiera a la
  /// cabeza en cualquier orientación; en dispositivo quedaba demasiado
  /// cerrado y centrado en las cejas, y el mapeo terminaba fuera del cuadro.
  /// La franja fija encuadra bien en la práctica.
  static img.Image _cropEyeBand(img.Image src) {
    final y = (src.height * 0.22).round().clamp(0, src.height - 1);
    final h = (src.height * 0.42).round().clamp(1, src.height - y);
    return img.copyCrop(src, x: 0, y: y, width: src.width, height: h);
  }
}
