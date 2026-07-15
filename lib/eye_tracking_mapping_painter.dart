import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'eye_tracking_model.dart';

/// Dibuja el mapping de pestañas (posiciones 7-13) sobre cada ojo detectado.
/// Se muestra como un abanico de líneas radiando desde un pivote debajo del ojo,
/// con números en los extremos y un arco suave conectando las puntas.
class LashMappingPainter extends CustomPainter {
  final TrackingFrame? frame;

  const LashMappingPainter({required this.frame});

  /// Misma lógica de transformación usada en el resto del tracking (BoxFit.cover / FILL_CENTER).
  Matrix4? _imageToCanvas(Size canvasSize) {
    final f = frame;
    if (f == null) return null;
    final iw = f.imageWidth.toDouble();
    final ih = f.imageHeight.toDouble();
    if (iw <= 0 || ih <= 0) return null;
    final sx = canvasSize.width / iw;
    final sy = canvasSize.height / ih;
    final scale = math.max(sx, sy);
    final dx = (canvasSize.width - iw * scale) / 2;
    final dy = (canvasSize.height - ih * scale) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null || !f.faceDetected) return;

    final m = _imageToCanvas(size);
    canvas.save();
    if (m != null) canvas.transform(m.storage);

    if (f.leftEye.length >= 4) _drawEyeMapping(canvas, f, f.leftEye);
    if (f.rightEye.length >= 4) _drawEyeMapping(canvas, f, f.rightEye);

    canvas.restore();
  }

  void _drawEyeMapping(Canvas canvas, TrackingFrame frame, List<EyePoint> eye) {
    // Bounding box del ojo
    double minX = eye.first.x, maxX = eye.first.x;
    double minY = eye.first.y, maxY = eye.first.y;
    for (final p in eye) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final w = maxX - minX;
    final h = maxY - minY;
    if (w < 5 || h < 2) return;

    // Esquina interior (más cerca del centro del rostro) y exterior
    final faceCenter = frame.imageWidth / 2.0;
    EyePoint innerPt = eye.first, outerPt = eye.first;
    double minDist = double.infinity, maxDist = 0;
    for (final p in eye) {
      final d = (p.x - faceCenter).abs();
      if (d < minDist) {
        minDist = d;
        innerPt = p;
      }
      if (d > maxDist) {
        maxDist = d;
        outerPt = p;
      }
    }

    // Pivote del abanico: debajo del centro del ojo
    final pivX = (innerPt.x + outerPt.x) / 2;
    final pivY = maxY + h * 1.0;

    // Ángulos desde el pivote hacia cada esquina (apuntan hacia arriba = Y negativa)
    final aInner = math.atan2(innerPt.y - pivY, innerPt.x - pivX);
    final aOuter = math.atan2(outerPt.y - pivY, outerPt.x - pivX);

    // Longitud de las líneas: llegan hasta h*0.5 por encima del párpado superior
    final lineLen = (pivY - minY) + h * 0.5;

    // Paints
    final linePaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.82)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.60)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Punto pivote
    canvas.drawCircle(
      Offset(pivX, pivY),
      h * 0.12,
      Paint()
        ..color = const Color(0xFFD4AF37).withValues(alpha: 0.75)
        ..style = PaintingStyle.fill,
    );

    // Pequeño arco en la base del abanico (indica la línea del párpado)
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(pivX, pivY),
        width: h * 0.55,
        height: h * 0.55,
      ),
      aInner,
      aOuter - aInner,
      false,
      Paint()
        ..color = const Color(0xFFD4AF37).withValues(alpha: 0.45)
        ..strokeWidth = 0.9
        ..style = PaintingStyle.stroke,
    );

    // 7 líneas del abanico (posiciones 7-13)
    const numLines = 7;
    final tips = <Offset>[];

    for (int i = 0; i < numLines; i++) {
      final t = i / (numLines - 1);
      final angle = aInner + t * (aOuter - aInner);
      final tx = pivX + math.cos(angle) * lineLen;
      final ty = pivY + math.sin(angle) * lineLen;
      tips.add(Offset(tx, ty));

      // Línea central (posición 10) ligeramente más prominente
      final isCenter = i == 3;
      canvas.drawLine(
        Offset(pivX, pivY),
        Offset(tx, ty),
        linePaint
          ..strokeWidth = isCenter ? 1.6 : 1.1
          ..color = isCenter
              ? const Color(0xFFFFD700).withValues(alpha: 0.90)
              : const Color(0xFFD4AF37).withValues(alpha: 0.80),
      );
    }

    // Arco suave conectando las puntas (bezier cuadrático)
    if (tips.length >= 2) {
      final path = Path()..moveTo(tips.first.dx, tips.first.dy);
      for (int i = 0; i < tips.length - 1; i++) {
        final cp = Offset(
          (tips[i].dx + tips[i + 1].dx) / 2,
          (tips[i].dy + tips[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(tips[i].dx, tips[i].dy, cp.dx, cp.dy);
      }
      path.lineTo(tips.last.dx, tips.last.dy);
      canvas.drawPath(path, arcPaint);
    }

    // Etiquetas numéricas (7-13) en la punta de cada línea
    final fontSize = w * 0.20;
    for (int i = 0; i < numLines; i++) {
      final t = i / (numLines - 1);
      final angle = aInner + t * (aOuter - aInner);
      final tip = tips[i];
      final ext = fontSize * 1.15;
      final lx = tip.dx + math.cos(angle) * ext;
      final ly = tip.dy + math.sin(angle) * ext;

      final tp = TextPainter(
        text: TextSpan(
          text: '${7 + i}',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant LashMappingPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
