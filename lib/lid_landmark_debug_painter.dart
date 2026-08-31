import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'eye_tracking_model.dart';

/// DEBUG: Dibuja los landmarks del párpado sobre la cámara.
///
/// Colores:
/// 🟢 Verde  = párpado SUPERIOR (8 pts, landmarks MediaPipe)
/// 🔴 Rojo   = párpado INFERIOR (8 pts)
/// 🟡 Amarillo = centroide del párpado superior (ancla del motor 3D)
/// 🟠 Naranja tiny = posición REAL de la pestaña (LashEdgeDetector)
class LidLandmarkDebugPainter extends CustomPainter {
  final TrackingFrame? frame;

  const LidLandmarkDebugPainter({required this.frame});

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

    _drawEye(canvas, f.leftUpperLid, f.leftLowerLid, f.leftLashLine, 'L');
    _drawEye(canvas, f.rightUpperLid, f.rightLowerLid, f.rightLashLine, 'R');

    canvas.restore();
  }

  void _drawEye(
    Canvas canvas,
    List<EyePoint> upperLid,
    List<EyePoint> lowerLid,
    List<EyePoint> lashLine,
    String label,
  ) {
    if (upperLid.isEmpty && lowerLid.isEmpty) return;

    // ── Pintas base ──────────────────────────────────────────────────────
    final greenFill = Paint()..color = const Color(0xFF00FF00)..style = PaintingStyle.fill;
    final redFill   = Paint()..color = const Color(0xFFFF3333)..style = PaintingStyle.fill;
    final border    = Paint()..color = Colors.black..strokeWidth = 0.8..style = PaintingStyle.stroke;
    final greenLine = Paint()
      ..color = const Color(0xFF00FF88).withValues(alpha: 0.85)
      ..strokeWidth = 2.0..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final redLine   = Paint()
      ..color = const Color(0xFFFF4444).withValues(alpha: 0.6)
      ..strokeWidth = 1.2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;

    // ── Líneas de párpado inferior ────────────────────────────────────────
    if (lowerLid.length >= 2) {
      final p = Path()..moveTo(lowerLid.first.x, lowerLid.first.y);
      for (int i = 1; i < lowerLid.length; i++) p.lineTo(lowerLid[i].x, lowerLid[i].y);
      canvas.drawPath(p, redLine);
    }

    // ── Línea del párpado superior (verde) ───────────────────────────────
    if (upperLid.length >= 2) {
      final p = Path()..moveTo(upperLid.first.x, upperLid.first.y);
      for (int i = 1; i < upperLid.length; i++) p.lineTo(upperLid[i].x, upperLid[i].y);
      canvas.drawPath(p, greenLine);
    }

    // ── Puntos del párpado inferior (rojo) ───────────────────────────────
    for (int i = 0; i < lowerLid.length; i++) {
      final p = lowerLid[i];
      canvas.drawCircle(Offset(p.x, p.y), 3.0, redFill);
      canvas.drawCircle(Offset(p.x, p.y), 3.0, border);
      _label(canvas, p.x, p.y + 6, '$i', const Color(0xFFFF7777));
    }

    // ── Puntos del párpado superior (verde) ──────────────────────────────
    for (int i = 0; i < upperLid.length; i++) {
      final p = upperLid[i];
      canvas.drawCircle(Offset(p.x, p.y), 4.0, greenFill);
      canvas.drawCircle(Offset(p.x, p.y), 4.0, border);
      _label(canvas, p.x, p.y - 6, '${i + 8}', const Color(0xFF00FF00));
    }

    // ── Centroide del párpado superior (ancla del motor) ─────────────────
    if (upperLid.isNotEmpty) {
      final mx = upperLid.fold<double>(0, (s, p) => s + p.x) / upperLid.length;
      final my = upperLid.fold<double>(0, (s, p) => s + p.y) / upperLid.length;

      final anchorFill   = Paint()..color = const Color(0xFFFFFF00)..style = PaintingStyle.fill;
      final anchorStroke = Paint()..color = Colors.black..strokeWidth = 1.5..style = PaintingStyle.stroke;
      final crossPaint   = Paint()..color = Colors.black..strokeWidth = 1.5..style = PaintingStyle.stroke;

      canvas.drawCircle(Offset(mx, my), 7.0, anchorFill);
      canvas.drawCircle(Offset(mx, my), 7.0, anchorStroke);
      canvas.drawLine(Offset(mx - 10, my), Offset(mx + 10, my), crossPaint);
      canvas.drawLine(Offset(mx, my - 10), Offset(mx, my + 10), crossPaint);
      _label(canvas, mx, my - 12, 'ANCLA $label', const Color(0xFFFFFF00));

      // Bounding box del párpado superior
      final allX = upperLid.map((p) => p.x).toList();
      final allY = upperLid.map((p) => p.y).toList();
      final minX = allX.reduce(math.min);
      final maxX = allX.reduce(math.max);
      final minY = allY.reduce(math.min);
      final maxY = allY.reduce(math.max);
      final bboxPaint = Paint()
        ..color = const Color(0xFF00FFFF).withValues(alpha: 0.4)
        ..strokeWidth = 1.0..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTRB(minX, minY, maxX, maxY), bboxPaint);
      final eyeW = (maxX - minX).toInt();
      final eyeH = (maxY - minY).toInt();
      _label(canvas, maxX + 3, minY,     'W=$eyeW', const Color(0xFF00FFFF));
      _label(canvas, maxX + 3, minY + 7, 'H=$eyeH', const Color(0xFF00FFFF));
    }

    // ── Puntos REALES de pestaña (naranja tiny) — LashEdgeDetector ───────
    // Son los puntos donde realmente nace la pestaña visible en la imagen,
    // corregidos desde los landmarks de MediaPipe buscando el píxel más oscuro.
    if (lashLine.isNotEmpty) {
      // Línea de conexión entre los puntos de pestaña real
      if (lashLine.length >= 2) {
        final lashLinePaint = Paint()
          ..color = const Color(0xFFFF8800).withValues(alpha: 0.9)
          ..strokeWidth = 1.5..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
        final path = Path()..moveTo(lashLine.first.x, lashLine.first.y);
        for (int i = 1; i < lashLine.length; i++) {
          path.lineTo(lashLine[i].x, lashLine[i].y);
        }
        canvas.drawPath(path, lashLinePaint);
      }

      // Puntitos naranja super pequeños — la posición exacta de la pestaña real
      final lashDotFill = Paint()
        ..color = const Color(0xFFFF9900)
        ..style = PaintingStyle.fill;
      final lashDotBorder = Paint()
        ..color = Colors.black
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < lashLine.length; i++) {
        final p = lashLine[i];
        // Radio 2.0 — diminuto para diferenciarse de los verdes (r=4.0)
        canvas.drawCircle(Offset(p.x, p.y), 2.0, lashDotFill);
        canvas.drawCircle(Offset(p.x, p.y), 2.0, lashDotBorder);
      }

      // Leyenda en el primer punto
      if (lashLine.isNotEmpty) {
        _label(canvas, lashLine.first.x - 8, lashLine.first.y + 8,
            '● real', const Color(0xFFFF9900));
      }
    }
  }

  void _label(Canvas canvas, double x, double y, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 5,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 2),
            Shadow(color: Colors.black, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant LidLandmarkDebugPainter oldDelegate) =>
      oldDelegate.frame != frame;
}