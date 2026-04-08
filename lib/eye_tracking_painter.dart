import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'eye_tracking_model.dart';

class EyeTrackingPainter extends CustomPainter {
  final TrackingFrame? frame;
  /// 0 = COMPATIBLE, 1 = EXPLORAR (escala / estilo).
  final int filterIndex;
  /// Índice del carrusel: cambia el asset de textura.
  final int lashVariantIndex;
  /// Textura PNG del modelo de pestañas (mismo espacio que el preview).
  final ui.Image? lashTexture;

  EyeTrackingPainter({
    required this.frame,
    this.filterIndex = 0,
    this.lashVariantIndex = 0,
    this.lashTexture,
  });

  /// Igual que `PreviewView.ScaleType.FILL_CENTER` / `BoxFit.cover`.
  Matrix4? _imageToCanvas(Size canvasSize) {
    final f = frame;
    if (f == null) return null;
    final iw = f.imageWidth;
    final ih = f.imageHeight;
    if (iw <= 0 || ih <= 0) return null;

    final sx = canvasSize.width / iw;
    final sy = canvasSize.height / ih;
    final scale = math.max(sx, sy);
    final dx = (canvasSize.width - iw * scale) / 2;
    final dy = (canvasSize.height - ih * scale) / 2;

    return Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null || !f.faceDetected) return;

    final m = _imageToCanvas(size);
    canvas.save();
    if (m != null) {
      canvas.transform(m.storage);
    }

    // Solo overlay de pestañas (sin contorno ni puntos de debug).
    // _drawFaceContour(canvas, f.faceContour);
    // _drawEye(canvas, f.leftEye, f.leftIris, Colors.greenAccent);
    // _drawEye(canvas, f.rightEye, f.rightIris, Colors.cyanAccent);

    final tex = lashTexture;
    if (tex != null) {
      final styleScale = (filterIndex == 0 ? 0.94 : 1.08) *
          (1.0 + (lashVariantIndex % 5) * 0.028);
      if (f.leftEye.length >= 4) {
        _drawArLashOverlay(
          canvas,
          f,
          f.leftEye,
          tex,
          styleScale: styleScale,
        );
      }
      if (f.rightEye.length >= 4) {
        _drawArLashOverlay(
          canvas,
          f,
          f.rightEye,
          tex,
          styleScale: styleScale,
        );
      }
    }

    canvas.restore();
  }

  /// Superpone la textura siguiendo el arco superior del ojo (coordenadas del frame).
  void _drawArLashOverlay(
    Canvas canvas,
    TrackingFrame frame,
    List<EyePoint> eye,
    ui.Image texture, {
    required double styleScale,
  }) {
    if (eye.length < 4) return;

    double minY = eye.first.y;
    double maxY = eye.first.y;
    double minX = eye.first.x;
    double maxX = eye.first.x;
    double sx = 0;
    for (final p in eye) {
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      sx += p.x;
    }
    final n = eye.length;
    final cx = sx / n;
    final h = (maxY - minY).clamp(1.0, 9999.0);
    final w = (maxX - minX).clamp(1.0, 9999.0);

    // Un poco más abajo que el tercio superior: más cerca de la línea real de pestañas.
    final upper = eye.where((p) => p.y <= minY + h * 0.52).toList();
    if (upper.length < 2) return;
    upper.sort((a, b) => a.x.compareTo(b.x));

    final t0 = upper.first;
    final t1 = upper.last;
    final tx = t1.x - t0.x;
    final ty = t1.y - t0.y;
    if (tx * tx + ty * ty < 1e-6) return;

    // Normal perpendicular a la tangente del párpado; apuntar hacia arriba (menor Y).
    var nx = -ty;
    var ny = tx;
    final nlen = math.sqrt(nx * nx + ny * ny);
    nx /= nlen;
    ny /= nlen;
    if (ny > 0) {
      nx = -nx;
      ny = -ny;
    }

    double ax = 0;
    double ay = 0;
    for (final p in upper) {
      ax += p.x;
      ay += p.y;
    }
    ax /= upper.length;
    ay /= upper.length;

    final outwardNudge = w * 0.035;
    ax += nx * outwardNudge;
    ay += ny * outwardNudge;

    // Bajar en la imagen (+Y) respecto a ceja: situar sobre el arco de pestañas del landmark.
    ay += h * 0.09;

    // Eje del párpado + vuelta 180° para que el PNG coincida con la orientación real de las pestañas.
    final angle = math.atan2(nx, -ny) + math.pi;

    final imgW = texture.width.toDouble();
    final imgH = texture.height.toDouble();
    final dstW = w * 2.25 * styleScale;
    final dstH = dstW * imgH / imgW;

    // Espejo horizontal en el otro ojo (mayor X en el frame) para alinear el PNG.
    final midFace = frame.imageWidth > 0 ? frame.imageWidth / 2 : 0;
    final mirror = cx >= midFace;

    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(ax, ay);
    canvas.rotate(angle);
    if (mirror) {
      canvas.scale(-1.0, 1.0);
    }
    // Tras +π: afinar hacia la línea de pestañas (ligero ajuste hacia el párpado).
    final center = Offset(0, dstH * -0.05);
    final dst = Rect.fromCenter(center: center, width: dstW, height: dstH);
    canvas.drawImageRect(
      texture,
      Rect.fromLTWH(0, 0, imgW, imgH),
      dst,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EyeTrackingPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.filterIndex != filterIndex ||
        oldDelegate.lashVariantIndex != lashVariantIndex ||
        oldDelegate.lashTexture != lashTexture;
  }
}
