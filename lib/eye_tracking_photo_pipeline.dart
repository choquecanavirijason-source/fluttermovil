import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import 'eye_tracking_model.dart';

/// Captura la foto final del asistente de trabajo / recomendación IA:
/// overlay Flutter (pestañas + líneas de medición) + foto real de la cámara
/// frontal, compuestas y recortadas a la franja de ojos. Concentra toda la
/// dependencia de los paquetes `image` y `camera` fuera de la página.
class EyeTrackingPhotoPipeline {
  static const double _overlayPixelRatio = 2.0;
  static const double _eyeBandStartRatio = 0.22;
  static const double _eyeBandHeightRatio = 0.42;

  /// Inicio de la franja de ojos: la normal, o reflejada respecto del centro
  /// con la clienta echada (ver [_cropEyeBand]).
  static double _bandStart(bool flip) =>
      flip ? 1 - _eyeBandStartRatio - _eyeBandHeightRatio : _eyeBandStartRatio;

  /// Inicio y alto de la franja de ojos como fracción del alto — los mismos
  /// que usa [_cropEyeBand]. El recorte nativo (`cropPhotoBand`) los recibe
  /// de acá para que haya una sola fuente de verdad.
  static ({double start, double height}) eyeBandRatios({
    bool flipEyeBand = false,
  }) => (start: _bandStart(flipEyeBand), height: _eyeBandHeightRatio);

  final GlobalKey previewCaptureKey;

  const EyeTrackingPhotoPipeline({required this.previewCaptureKey});

  Size? get previewSize {
    final boundary =
        previewCaptureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || !boundary.attached) return null;
    return boundary.size;
  }

  /// Proyecta los landmarks al eye band usando el mismo `BoxFit.cover` del
  /// preview y la misma banda vertical aplicada a la foto capturada.
  static TrackingFrame? frameForCapturedBand(
    TrackingFrame? frame,
    Size previewSize, {
    bool rotate180 = false,
    bool flipEyeBand = false,
  }) {
    if (frame == null ||
        !frame.faceDetected ||
        frame.imageWidth <= 0 ||
        frame.imageHeight <= 0 ||
        previewSize.width <= 0 ||
        previewSize.height <= 0) {
      return null;
    }

    final sourceWidth = frame.imageWidth.toDouble();
    final sourceHeight = frame.imageHeight.toDouble();
    final scale = math.max(
      previewSize.width / sourceWidth,
      previewSize.height / sourceHeight,
    );
    final dx = (previewSize.width - sourceWidth * scale) / 2;
    final dy = (previewSize.height - sourceHeight * scale) / 2;
    final overlayWidth = (previewSize.width * _overlayPixelRatio).round();
    final overlayHeight = (previewSize.height * _overlayPixelRatio).round();
    final cropTop = (overlayHeight * _bandStart(flipEyeBand)).round();
    final bandHeight = (overlayHeight * _eyeBandHeightRatio).round().clamp(
      1,
      overlayHeight - cropTop,
    );

    EyePoint project(EyePoint point) {
      final x = (point.x * scale + dx) * _overlayPixelRatio;
      final y = (point.y * scale + dy) * _overlayPixelRatio - cropTop;
      return EyePoint(
        x: rotate180 ? overlayWidth - 1 - x : x,
        y: rotate180 ? bandHeight - 1 - y : y,
      );
    }

    List<EyePoint> projectAll(List<EyePoint> points) =>
        points.map(project).toList(growable: false);

    return TrackingFrame(
      faceDetected: frame.faceDetected,
      imageWidth: overlayWidth,
      imageHeight: bandHeight,
      faceContour: projectAll(frame.faceContour),
      leftEye: projectAll(frame.leftEye),
      rightEye: projectAll(frame.rightEye),
      leftIris: frame.leftIris == null ? null : project(frame.leftIris!),
      rightIris: frame.rightIris == null ? null : project(frame.rightIris!),
      leftOpenRatio: frame.leftOpenRatio,
      rightOpenRatio: frame.rightOpenRatio,
      leftUpperLid: projectAll(frame.leftUpperLid),
      leftLowerLid: projectAll(frame.leftLowerLid),
      rightUpperLid: projectAll(frame.rightUpperLid),
      rightLowerLid: projectAll(frame.rightLowerLid),
      leftLashLine: projectAll(frame.leftLashLine),
      rightLashLine: projectAll(frame.rightLashLine),
    );
  }

  /// Rota los landmarks de una banda ya proyectada para que sigan coincidiendo
  /// con la imagen cuando el usuario la gira manualmente en resultados.
  static TrackingFrame? rotateFrame180(TrackingFrame? frame) {
    if (frame == null) return null;
    EyePoint rotate(EyePoint point) =>
        EyePoint(x: frame.imageWidth - point.x, y: frame.imageHeight - point.y);
    List<EyePoint> rotateAll(List<EyePoint> points) =>
        points.map(rotate).toList(growable: false);

    return TrackingFrame(
      faceDetected: frame.faceDetected,
      imageWidth: frame.imageWidth,
      imageHeight: frame.imageHeight,
      faceContour: rotateAll(frame.faceContour),
      leftEye: rotateAll(frame.leftEye),
      rightEye: rotateAll(frame.rightEye),
      leftIris: frame.leftIris == null ? null : rotate(frame.leftIris!),
      rightIris: frame.rightIris == null ? null : rotate(frame.rightIris!),
      leftOpenRatio: frame.leftOpenRatio,
      rightOpenRatio: frame.rightOpenRatio,
      leftUpperLid: rotateAll(frame.leftUpperLid),
      leftLowerLid: rotateAll(frame.leftLowerLid),
      rightUpperLid: rotateAll(frame.rightUpperLid),
      rightLowerLid: rotateAll(frame.rightLowerLid),
      leftLashLine: rotateAll(frame.leftLashLine),
      rightLashLine: rotateAll(frame.rightLashLine),
    );
  }

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
      final image = await boundary.toImage(pixelRatio: _overlayPixelRatio);
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
    bool flipEyeBand = false,
    ({int width, int height})? overlaySize,
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

      return await compositeAndCropInBackground(
        faceBytes,
        overlayBytes,
        mirror: preferFrontCamera,
        flipEyeBand: flipEyeBand,
        overlaySize: overlaySize,
      );
    } catch (e) {
      debugPrint('captureAndComposite: $e');
      return overlayBytes;
    } finally {
      await ctrl?.dispose();
    }
  }

  /// [compositeAndCrop] en un isolate aparte. Decodificar, escalar y
  /// codificar con el paquete `image` (Dart puro) toma cientos de ms
  /// a segundos: en el hilo de la UI congelaba la pantalla y el aviso de
  /// "procesando" mientras tanto.
  static Future<Uint8List> compositeAndCropInBackground(
    Uint8List faceRaw,
    Uint8List? overlayRaw, {
    bool mirror = true,
    bool rotate180 = false,
    bool flipEyeBand = false,
    ({int width, int height})? overlaySize,
  }) {
    return Isolate.run(
      () => compositeAndCrop(
        faceRaw,
        overlayRaw,
        mirror: mirror,
        rotate180: rotate180,
        flipEyeBand: flipEyeBand,
        overlaySize: overlaySize,
      ),
    );
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
  ///
  /// [overlaySize] reemplaza a [overlayRaw] cuando el overlay estaría VACÍO
  /// (ver `captureOverlayIsEmpty` en `eye_tracking_page.dart`): de él sólo
  /// importaban sus medidas, que fijan el encuadre y el tamaño final. Con
  /// esto la foto sale idéntica, píxel por píxel, sin capturar, codificar,
  /// decodificar ni mezclar una imagen transparente — que era buena parte de
  /// la demora. Si vienen los dos, manda [overlayRaw].
  static Uint8List compositeAndCrop(
    Uint8List faceRaw,
    Uint8List? overlayRaw, {
    bool mirror = true,
    bool rotate180 = false,
    bool flipEyeBand = false,
    ({int width, int height})? overlaySize,
  }) {
    final timing = Stopwatch()..start(); // TEMPORAL — ver CaptureTiming.
    var faceImg = img.decodeImage(faceRaw);
    if (faceImg == null) return faceRaw;
    final decodeMs = timing.elapsedMilliseconds;

    // Aplica la rotación EXIF (la foto suele guardarse apaisada + tag de giro).
    faceImg = img.bakeOrientation(faceImg);

    var canvas = mirror ? img.flipHorizontal(faceImg) : faceImg;
    final orientMs = timing.elapsedMilliseconds;

    final overlayImg = overlayRaw == null ? null : img.decodeImage(overlayRaw);
    final overlayDecodeMs = timing.elapsedMilliseconds;
    final overlayW = overlayImg?.width ?? overlaySize?.width;
    final overlayH = overlayImg?.height ?? overlaySize?.height;
    if (overlayW != null && overlayH != null && overlayW > 0 && overlayH > 0) {
      // El preview usa BoxFit.cover: la pantalla solo muestra un recorte
      // centrado de la foto. Recortamos la foto a la proporción del overlay
      // (pantalla) ANTES de componer; si no, las pestañas quedan corridas.
      final overlayAspect = overlayW / overlayH;
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
      canvas = _cropEyeBand(canvas, flipEyeBand);
      var overlayBand = overlayImg == null
          ? null
          : _cropEyeBand(overlayImg, flipEyeBand);
      // Medidas de la franja del overlay, iguales tenga o no imagen.
      final bandRows = _bandRows(overlayH, flipEyeBand);
      final bandW = overlayW;
      final bandH = bandRows.height;
      if (rotate180) {
        // Girar después del recorte mantiene la foto, el overlay y los
        // landmarks en el mismo sistema de coordenadas de la banda.
        canvas = img.copyRotate(canvas, angle: 180);
        if (overlayBand != null) {
          overlayBand = img.copyRotate(overlayBand, angle: 180);
        }
      }

      // Se compone a la resolución del OVERLAY y no a la de la foto: el
      // mapeo son líneas finas y números, y encogerlos a ~480p (lo que
      // mide la foto) era lo que los dejaba pixelados. Escalando la foto
      // hacia arriba, el mapeo entra 1:1 y queda limpio.
      //
      // Lineal y no cúbica: la cúbica muestrea 16 píxeles por píxel de
      // salida en Dart puro y era de lo más lento de la captura; sobre la
      // FOTO (no sobre las líneas del mapeo, que entran 1:1) la diferencia
      // no se nota.
      if (bandW > canvas.width) {
        canvas = img.copyResize(
          canvas,
          width: bandW,
          height: bandH,
          interpolation: img.Interpolation.linear,
        );
        if (overlayBand != null) {
          img.compositeImage(canvas, overlayBand, blend: img.BlendMode.alpha);
        }
      } else if (overlayBand != null) {
        final overlayScaled = img.copyResize(
          overlayBand,
          width: canvas.width,
          height: canvas.height,
          interpolation: img.Interpolation.linear,
        );
        img.compositeImage(canvas, overlayScaled, blend: img.BlendMode.alpha);
      }
      final composeMs = timing.elapsedMilliseconds;
      final out = _encode(canvas);
      _logTiming(
        decodeMs: decodeMs,
        orientMs: orientMs,
        overlayDecodeMs: overlayDecodeMs,
        composeMs: composeMs,
        totalMs: timing.elapsedMilliseconds,
        withOverlay: overlayImg != null,
        outW: canvas.width,
        outH: canvas.height,
      );
      return out;
    }

    var cropped = _cropEyeBand(canvas, flipEyeBand);
    if (rotate180) cropped = img.copyRotate(cropped, angle: 180);
    return _encode(cropped);
  }

  /// TEMPORAL — tiempos de [compositeAndCrop] por paso, acumulados desde el
  /// inicio (filtrar logcat por `CaptureTiming`). Borrar cuando se cierre la
  /// medición de velocidad.
  static void _logTiming({
    required int decodeMs,
    required int orientMs,
    required int overlayDecodeMs,
    required int composeMs,
    required int totalMs,
    required bool withOverlay,
    required int outW,
    required int outH,
  }) {
    debugPrint(
      'CaptureTiming composicion: decodificarFoto=${decodeMs}ms '
      'orientar=${orientMs}ms decodificarOverlay=${overlayDecodeMs}ms '
      'recortar+escalar+mezclar=${composeMs}ms total(con JPEG)=${totalMs}ms '
      'overlay=${withOverlay ? 'PNG' : 'solo medidas'} salida=${outW}x$outH',
    );
  }

  /// JPEG y no PNG: el resultado es una foto (solo se muestra con
  /// `Image.memory` y la IA la recibe como `.jpg`), y codificar PNG de ~2 MP
  /// en Dart puro tomaba segundos — era la mayor parte de la demora al
  /// capturar. 92 conserva nítidas las líneas y los números del mapeo.
  static Uint8List _encode(img.Image image) =>
      Uint8List.fromList(img.encodeJpg(image, quality: 92));

  /// Franja de los ojos: y=22%–64% del alto, a todo lo ancho.
  ///
  /// Se probó derivar el recorte de los landmarks para que siguiera a la
  /// cabeza en cualquier orientación; en dispositivo quedaba demasiado
  /// cerrado y centrado en las cejas, y el mapeo terminaba fuera del cuadro.
  /// La franja fija encuadra bien en la práctica.
  ///
  /// [flip] = clienta echada: la guía de encuadre se dibuja girada 180°, así
  /// que los ojos quedan reflejados respecto del centro (~60 % del alto en
  /// vez de ~40 %) y la franja se refleja igual: y=36%–78%.
  static img.Image _cropEyeBand(img.Image src, [bool flip = false]) {
    final rows = _bandRows(src.height, flip);
    return img.copyCrop(
      src,
      x: 0,
      y: rows.y,
      width: src.width,
      height: rows.height,
    );
  }

  /// Filas de la franja de ojos para una imagen de [height] de alto. Única
  /// fuente del redondeo, para que la franja calculada sólo con medidas
  /// ([compositeAndCrop] con `overlaySize`) sea idéntica a la recortada.
  static ({int y, int height}) _bandRows(int height, bool flip) {
    final y = (height * _bandStart(flip)).round().clamp(0, height - 1);
    final h = (height * _eyeBandHeightRatio).round().clamp(1, height - y);
    return (y: y, height: h);
  }

  /// Medidas en píxeles que tendría el overlay capturado por
  /// [captureOverlay] para una vista de [previewSize] — mismo redondeo que
  /// `RenderRepaintBoundary.toImage` (hacia arriba).
  static ({int width, int height}) overlayPixelSize(Size previewSize) => (
    width: (previewSize.width * _overlayPixelRatio).ceil(),
    height: (previewSize.height * _overlayPixelRatio).ceil(),
  );
}
