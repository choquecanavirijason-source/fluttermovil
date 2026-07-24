import 'package:flutter/material.dart';

/// Dibuja la franja de alineación de ojos que se muestra antes de capturar
/// la foto (asistente de trabajo / recomendación IA): oscurece todo excepto
/// una franja central y=22%–64% del alto (misma franja que recorta
/// `EyeTrackingPhotoPipeline.compositeAndCrop`), con contorno blanco por
/// defecto y verde cuando [aligned] es true.
class EyePositionGuidePainter extends CustomPainter {
  final bool aligned;

  const EyePositionGuidePainter({required this.aligned});

  @override
  void paint(Canvas canvas, Size size) {
    final bandRect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.22,
      size.width * 0.84,
      size.height * 0.42,
    );
    final rrect = RRect.fromRectAndRadius(bandRect, const Radius.circular(24));

    final outerPath = Path()..addRect(Offset.zero & size);
    final innerPath = Path()..addRRect(rrect);
    final maskPath = Path.combine(
      PathOperation.difference,
      outerPath,
      innerPath,
    );
    canvas.drawPath(maskPath, Paint()..color = const Color(0x99000000));

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = aligned ? const Color(0xFF2ECC71) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 3.5 : 2.5,
    );
  }

  @override
  bool shouldRepaint(EyePositionGuidePainter old) => old.aligned != aligned;
}
