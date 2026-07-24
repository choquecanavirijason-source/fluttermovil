import 'dart:math' as math;
import 'dart:ui';

import 'eye_tracking_model.dart';

/// Matemática pura para la guía de alineación de ojos que se muestra antes
/// de capturar la foto (asistente de trabajo / recomendación IA). Sin
/// `BuildContext` ni estado: solo geometría sobre un [TrackingFrame] y el
/// tamaño del canvas donde se dibuja la guía.
class EyeAlignmentGuide {
  const EyeAlignmentGuide._();

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

  /// Misma transformación imagen→pantalla que usa `LashMappingPainter`
  /// (BoxFit.cover), para comparar ojos detectados contra la posición de la
  /// guía dibujada en pantalla (misma franja que
  /// `EyePositionGuidePainter`/`EyeTrackingPhotoPipeline.compositeAndCrop`).
  static bool isAligned(TrackingFrame frame, Size canvasSize) {
    if (!frame.faceDetected) return false;
    final iw = frame.imageWidth.toDouble();
    final ih = frame.imageHeight.toDouble();
    if (iw <= 0 || ih <= 0) return false;

    final a = anchorFor(frame.leftEye, frame.leftIris);
    final b = anchorFor(frame.rightEye, frame.rightIris);
    if (a == null || b == null) return false;

    final sx = canvasSize.width / iw;
    final sy = canvasSize.height / ih;
    final scale = math.max(sx, sy);
    final dx = (canvasSize.width - iw * scale) / 2;
    final dy = (canvasSize.height - ih * scale) / 2;
    Offset toCanvas(EyePoint p) => Offset(p.x * scale + dx, p.y * scale + dy);

    final pa = toCanvas(a);
    final pb = toCanvas(b);
    // Asigna cada ojo detectado a la guía más cercana en X, sin asumir a qué
    // lado de la pantalla corresponde "leftEye"/"rightEye".
    final detectedLeft = pa.dx <= pb.dx ? pa : pb;
    final detectedRight = pa.dx <= pb.dx ? pb : pa;

    final bandTop = canvasSize.height * 0.22;
    final bandHeight = canvasSize.height * 0.42;
    final eyeY = bandTop + bandHeight / 2;
    final guideLeft = Offset(canvasSize.width * 0.32, eyeY);
    final guideRight = Offset(canvasSize.width * 0.68, eyeY);
    final tolerance = canvasSize.width * 0.11;

    return (detectedLeft - guideLeft).distance <= tolerance &&
        (detectedRight - guideRight).distance <= tolerance;
  }
}
