import 'dart:math' as math;
import 'dart:ui';

import 'eye_tracking_model.dart';

/// Resultado de evaluar un [TrackingFrame] contra la guía de alineación:
/// dos condiciones independientes, ambas necesarias antes de capturar la
/// foto para el asistente de trabajo / recomendación IA.
class AlignmentStatus {
  /// El óvalo de rostro (`faceContour`) está centrado y del tamaño esperado
  /// dentro de la guía fija dibujada en pantalla.
  final bool faceFramed;

  /// Ambos ojos están cerrados (necesario para mapear la línea de
  /// pestañas — con los ojos abiertos el párpado tapa la base real).
  final bool eyesClosed;

  const AlignmentStatus({required this.faceFramed, required this.eyesClosed});

  bool get ready => faceFramed && eyesClosed;

  static const AlignmentStatus none = AlignmentStatus(
    faceFramed: false,
    eyesClosed: false,
  );
}

/// Matemática pura para la guía de alineación de ojos que se muestra antes
/// de capturar la foto (asistente de trabajo / recomendación IA). Sin
/// `BuildContext` ni estado: solo geometría sobre un [TrackingFrame] y el
/// tamaño del canvas donde se dibuja la guía.
class EyeAlignmentGuide {
  const EyeAlignmentGuide._();

  /// Tolerancias del encuadre, juntas para poder calibrarlas de un vistazo.
  ///
  /// Estaban demasiado ajustadas: obligaban a encuadrar prácticamente de los
  /// labios a la coronilla para que la guía se diera por buena. Con la
  /// clienta acostada y el teléfono en la mano eso es incómodo de sostener,
  /// así que se abrió el rango. Siguen cumpliendo su función —evitar
  /// disparar la captura con el rostro lejos, cortado o corrido— pero sin
  /// exigir una posición milimétrica.
  ///
  /// [_minSizeRatio]/[_maxSizeRatio] son el largo frente→mentón medido
  /// contra el alto del óvalo de guía; [_centerTolerance] es cuánto puede
  /// alejarse el centro del rostro del centro de la guía, en fracción del
  /// ancho de pantalla.
  static const double _minSizeRatio = 0.45;
  static const double _maxSizeRatio = 1.60;
  static const double _centerTolerance = 0.17;

  /// Única fuente de la geometría de la guía: la usa tanto
  /// `EyePositionGuidePainter` (para dibujar el óvalo) como este archivo
  /// (para decidir si el rostro real está encuadrado dentro de ella). Cubre
  /// el ROSTRO COMPLETO (frente a mentón, como las guías de verificación de
  /// identidad de un banco) — no la franja angosta de solo ojos que usa
  /// `EyeTrackingPhotoPipeline.compositeAndCrop` para el recorte final (esa
  /// franja es independiente y no necesita coincidir con esta guía visual).
  static Rect guideRect(Size canvasSize) => Rect.fromLTWH(
    canvasSize.width * 0.14,
    canvasSize.height * 0.16,
    canvasSize.width * 0.72,
    canvasSize.height * 0.56,
  );

  /// Centro de un ojo: usa el iris (más preciso) si está disponible, si no,
  /// el centroide de los puntos de contorno del ojo.
  static EyePoint? anchorFor(List<EyePoint> contour, EyePoint? iris) {
    if (iris != null) return iris;
    if (contour.isEmpty) return null;
    double sx = 0, sy = 0;
    for (final p in contour) {
      sx += p.x;
      sy += p.y;
    }
    return EyePoint(x: sx / contour.length, y: sy / contour.length);
  }

  /// Transform imagen→pantalla (BoxFit.cover), igual que `LashMappingPainter`.
  static Offset Function(EyePoint) _toCanvas(TrackingFrame frame, Size size) {
    final iw = frame.imageWidth.toDouble();
    final ih = frame.imageHeight.toDouble();
    final sx = size.width / iw;
    final sy = size.height / ih;
    final scale = math.max(sx, sy);
    final dx = (size.width - iw * scale) / 2;
    final dy = (size.height - ih * scale) / 2;
    return (EyePoint p) => Offset(p.x * scale + dx, p.y * scale + dy);
  }

  /// ¿El rostro detectado está centrado y del tamaño esperado dentro de la
  /// guía fija (mismo rect que dibuja el óvalo de `EyePositionGuidePainter`)?
  /// Evita disparar la captura demasiado lejos, demasiado cerca, o corrido
  /// hacia un costado.
  ///
  /// El tamaño se mide como la distancia FRENTE→MENTÓN (`faceContour[0]` y
  /// `faceContour[18]`, por el orden fijo del óvalo facial de MediaPipe) y
  /// no con el ancho/alto del bounding box: la clienta trabaja acostada y la
  /// operaria filma desde la cabecera, así que la cabeza llega volcada o
  /// inclinada, y ahí un bounding box en ejes de imagen cambia de forma y el
  /// chequeo falla aunque el encuadre esté bien.
  static bool isFaceFramed(TrackingFrame frame, Size canvasSize) {
    if (!frame.faceDetected || frame.faceContour.length < 19) return false;
    final iw = frame.imageWidth.toDouble();
    final ih = frame.imageHeight.toDouble();
    if (iw <= 0 || ih <= 0) return false;

    final toCanvas = _toCanvas(frame, canvasSize);

    double sumX = 0, sumY = 0;
    for (final p in frame.faceContour) {
      final c = toCanvas(p);
      sumX += c.dx;
      sumY += c.dy;
    }
    final n = frame.faceContour.length;
    final faceCenter = Offset(sumX / n, sumY / n);

    final forehead = toCanvas(frame.faceContour[0]);
    final chin = toCanvas(frame.faceContour[18]);
    final faceLength = (chin - forehead).distance;
    if (faceLength <= 0) return false;

    final guide = guideRect(canvasSize);
    final centerTolerance = canvasSize.width * _centerTolerance;
    final centered = (faceCenter - guide.center).distance <= centerTolerance;

    // El alto del óvalo de guía representa el largo del rostro.
    final sizeRatio = faceLength / guide.height;
    final sizedOk = sizeRatio >= _minSizeRatio && sizeRatio <= _maxSizeRatio;

    return centered && sizedOk;
  }

  /// Apertura del ojo como fracción de su largo: baja (~0.05-0.15) con el
  /// ojo cerrado, más alta (~0.28+) con el ojo abierto. `null` si no hay
  /// suficientes puntos.
  ///
  /// Se mide sobre el EJE DEL OJO (el par de landmarks más separados son
  /// sus dos esquinas) y no con un bounding box en ejes de imagen: con la
  /// cabeza inclinada —que es la norma acá, la operaria filma desde la
  /// cabecera con la clienta acostada— un ojo cerrado pero en diagonal
  /// infla el "alto" del bounding box y daría siempre "abierto".
  static double? eyeOpenRatio(List<EyePoint> eye) {
    if (eye.length < 4) return null;

    EyePoint a = eye.first, b = eye.first;
    double bestSq = -1;
    for (int i = 0; i < eye.length; i++) {
      for (int j = i + 1; j < eye.length; j++) {
        final dx = eye[i].x - eye[j].x;
        final dy = eye[i].y - eye[j].y;
        final dSq = dx * dx + dy * dy;
        if (dSq > bestSq) {
          bestSq = dSq;
          a = eye[i];
          b = eye[j];
        }
      }
    }
    final len = math.sqrt(bestSq);
    if (len <= 0) return null;

    // Normal al eje del ojo: la extensión de los puntos sobre ella es la
    // apertura real del párpado, sin importar cómo esté rotada la cabeza.
    final nx = -(b.y - a.y) / len;
    final ny = (b.x - a.x) / len;
    double minPerp = double.infinity, maxPerp = -double.infinity;
    for (final p in eye) {
      final perp = (p.x - a.x) * nx + (p.y - a.y) * ny;
      if (perp < minPerp) minPerp = perp;
      if (perp > maxPerp) maxPerp = perp;
    }

    return (maxPerp - minPerp) / len;
  }

  /// Umbral por debajo del cual se considera el ojo cerrado. Los umbrales de
  /// `EyeShapeAnalyzer` para ojos ABIERTOS parten de aspect (ancho/alto) <=
  /// 3.6, es decir alto/ancho >= ~0.28 — bien por encima de este corte.
  static const double _closedRatioThreshold = 0.16;

  /// ¿Ambos ojos están cerrados? Necesario antes de capturar la foto de
  /// referencia para mapear la línea de pestañas (con el ojo abierto el
  /// párpado tapa la base real de la pestaña).
  static bool isEyesClosed(TrackingFrame frame) {
    if (!frame.faceDetected) return false;
    final left = eyeOpenRatio(frame.leftEye);
    final right = eyeOpenRatio(frame.rightEye);
    if (left == null || right == null) return false;
    return left <= _closedRatioThreshold && right <= _closedRatioThreshold;
  }

  /// Evalúa ambas condiciones de una sola pasada.
  static AlignmentStatus evaluate(TrackingFrame frame, Size canvasSize) {
    return AlignmentStatus(
      faceFramed: isFaceFramed(frame, canvasSize),
      eyesClosed: isEyesClosed(frame),
    );
  }
}
