import 'package:flutter/material.dart';
import '../../eye_tracking_alignment.dart';

/// Dibuja la guía de alineación (silueta de rostro, no un rectángulo) que se
/// muestra antes de capturar la foto (asistente de trabajo / recomendación
/// IA) — como las guías de verificación de identidad de un banco: UN solo
/// óvalo fijo donde el usuario debe encajar su rostro COMPLETO (frente a
/// mentón). El rect base es `EyeAlignmentGuide.guideRect` (única fuente,
/// compartida con la lógica que decide si el rostro está encuadrado). El
/// color del contorno refleja las DOS condiciones necesarias para disparar
/// la captura:
///   - blanco: el rostro todavía no está encuadrado en la guía.
///   - ámbar: el rostro ya está encuadrado, falta cerrar los ojos.
///   - verde: ambas condiciones listas.
class EyePositionGuidePainter extends CustomPainter {
  final bool faceFramed;
  final bool eyesClosed;

  const EyePositionGuidePainter({
    required this.faceFramed,
    required this.eyesClosed,
  });

  Color get _color {
    if (faceFramed && eyesClosed) return const Color(0xFF2ECC71);
    if (faceFramed) return const Color(0xFFFFC107);
    return Colors.white;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final facePath = _faceGuidePath(EyeAlignmentGuide.guideRect(size));

    final outerPath = Path()..addRect(Offset.zero & size);
    final maskPath = Path.combine(
      PathOperation.difference,
      outerPath,
      facePath,
    );
    canvas.drawPath(maskPath, Paint()..color = const Color(0x99000000));

    canvas.drawPath(
      facePath,
      Paint()
        ..color = _color
        ..style = PaintingStyle.stroke
        ..strokeWidth = faceFramed ? 3.5 : 2.5,
    );
  }

  /// Óvalo simple (elipse) inscrito en [rect] — como la guía "OVAL" clásica
  /// de detectores de forma de rostro (Instagram/apps de maquillaje). Se
  /// probaron formas con "cintura" en la sien (armónicos) y taper fuerte de
  /// mentón: se veían con bultos raros, no como rostro. Un óvalo liso es lo
  /// que de verdad se usa en ese tipo de guías.
  Path _faceGuidePath(Rect rect) => Path()..addOval(rect);

  @override
  bool shouldRepaint(EyePositionGuidePainter old) =>
      old.faceFramed != faceFramed || old.eyesClosed != eyesClosed;
}
