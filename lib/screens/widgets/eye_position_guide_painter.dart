import 'package:flutter/material.dart';
import '../../eye_tracking_alignment.dart';

/// Dibuja la guía de alineación (silueta de rostro, no un rectángulo) que se
/// muestra antes de capturar la foto (asistente de trabajo / recomendación
/// IA) — como las guías de verificación de identidad de un banco: UN solo
/// óvalo fijo donde el usuario debe encajar su rostro COMPLETO (frente a
/// mentón). El rect base es `EyeAlignmentGuide.guideRect` (única fuente,
/// compartida con la lógica que decide si el rostro está encuadrado). El
/// Óvalo y guías de nariz/ojos comparten el color del detector de ojos
/// cerrados, independientemente de las demás condiciones de captura.
class EyePositionGuidePainter extends CustomPainter {
  final bool eyesClosed;

  const EyePositionGuidePainter({required this.eyesClosed});

  Color get _color => eyesClosed ? Colors.greenAccent : Colors.white54;

  @override
  void paint(Canvas canvas, Size size) {
    final guideRect = EyeAlignmentGuide.guideRect(size);
    final facePath = _faceGuidePath(guideRect);

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
        ..strokeWidth = eyesClosed ? 3.5 : 2.5,
    );

    final guidePaint = Paint()
      ..color = _color
      ..strokeWidth = eyesClosed ? 2.2 : 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final eyeLineY = guideRect.top + guideRect.height / 3;
    _drawDashedLine(
      canvas,
      Offset(guideRect.left + guideRect.width * 0.18, eyeLineY),
      Offset(guideRect.right - guideRect.width * 0.18, eyeLineY),
      guidePaint,
    );
    _drawDashedLine(
      canvas,
      Offset(guideRect.center.dx, guideRect.top + guideRect.height * 0.12),
      Offset(guideRect.center.dx, guideRect.bottom - guideRect.height * 0.12),
      guidePaint,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final delta = end - start;
    final length = delta.distance;
    if (length <= 0) return;
    final direction = delta / length;
    const dashLength = 7.0;
    const gapLength = 5.0;
    for (double offset = 0; offset < length; offset += dashLength + gapLength) {
      final dashEnd = (offset + dashLength).clamp(0.0, length);
      canvas.drawLine(start + direction * offset, start + direction * dashEnd, paint);
    }
  }

  /// Óvalo simple (elipse) inscrito en [rect] — como la guía "OVAL" clásica
  /// de detectores de forma de rostro (Instagram/apps de maquillaje). Se
  /// probaron formas con "cintura" en la sien (armónicos) y taper fuerte de
  /// mentón: se veían con bultos raros, no como rostro. Un óvalo liso es lo
  /// que de verdad se usa en ese tipo de guías.
  Path _faceGuidePath(Rect rect) => Path()..addOval(rect);

  @override
  bool shouldRepaint(EyePositionGuidePainter old) =>
      old.eyesClosed != eyesClosed;
}
