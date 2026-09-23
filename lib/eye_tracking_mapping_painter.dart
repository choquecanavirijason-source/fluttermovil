import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'eye_tracking_model.dart';

/// Patrón de mapeo de pestañas: qué número (largo de pestaña) va en cada
/// posición a lo largo del párpado, y si el LARGO dibujado de cada línea
/// varía según ese número (`variableLength: true`) o si todas las líneas
/// miden lo mismo y los números son solo etiquetas (`variableLength: false`,
/// el abanico genérico para diseños sin patrón propio).
///
/// Referencias reales confirmadas por la usuaria (fotos de mapeo aplicado
/// sobre clienta real, no diagramas de stock):
///   - Cat Eye: 9,10,11,12,13,14 — sube parejo de la esquina interna a la
///     externa, SIN bajar de nuevo.
///   - Natural: 9,10,11,12,11,10 — sube y BAJA de nuevo, pico cerca del
///     centro, no hacia una esquina.
/// Ambas fotos también marcan tipo de curl por posición (C/CC/D) — eso
/// todavía no se dibuja acá, solo largo + número.
class _LashMappingPattern {
  final List<int> labels;
  final bool variableLength;

  const _LashMappingPattern(this.labels, {this.variableLength = false});
}

const _genericFanPattern = _LashMappingPattern([7, 8, 9, 10, 11, 12, 13]);
const _catEyePattern = _LashMappingPattern(
  [9, 10, 11, 12, 13, 14],
  variableLength: true,
);
const _naturalPattern = _LashMappingPattern(
  [9, 10, 11, 12, 11, 10],
  variableLength: true,
);

/// Máximo teórico usado para normalizar `variableLength` (el 14 de Cat Eye
/// es hoy el pico más alto de cualquier patrón — subir esto si más adelante
/// se agrega un patrón con un número más alto).
const _maxMappingLabel = 14;

/// Largo de la línea del número más alto, como fracción del ancho del ojo.
/// Todo se escala con el ANCHO y nunca con el alto: el alto colapsa a casi
/// cero con el ojo cerrado (que es justamente como se trabaja y como se
/// captura la foto de referencia), y eso encogía el mapeo entero.
///
/// Las líneas se dibujan hacia la MEJILLA (donde va el parche de hidrogel),
/// no hacia la ceja: así es como la estilista escribe el mapeo a mano sobre
/// el parche, y además no tapa las pestañas, que es justo lo que está
/// trabajando. 0.32 las deja dentro de la zona del parche — es el valor a
/// mover para calibrar cuánto se extienden.
const _maxLineLenRatio = 0.32;

/// Apertura del abanico y en qué punto del párpado queda la línea "recta".
/// Replica las referencias: las líneas del lado interno salen casi
/// perpendiculares a la línea de pestañas y las del lado externo se van
/// inclinando hacia afuera.
const _fanBias = 0.55;
const _fanPivotT = 0.30;

/// Cuánto se corre el mapeo desde la línea de pestañas hacia la mejilla, en
/// fracción del ancho del ojo.
///
/// 0.16 es el valor validado en dispositivo. Este es el número a mover si
/// queda muy encima de la pestaña o demasiado separado — y SOLO ese: si el
/// mapeo aparece del lado de las cejas, eso no se arregla acá, es la
/// dirección (ver [_towardCheek]).
const _lashLineOffsetRatio = 0.16;

_LashMappingPattern _patternForStyle(String? styleId) {
  switch (styleId) {
    case 'cateye':
      return _catEyePattern;
    case 'natural':
      return _naturalPattern;
    default:
      return _genericFanPattern;
  }
}

/// Dibuja el mapeo de pestañas sobre cada ojo detectado, con el patrón de
/// números/largos real del diseño activo ([styleId]) — no todos los diseños
/// mapean igual (ver [_LashMappingPattern]).
///
/// Cada línea nace sobre la LÍNEA DE PESTAÑAS real (los landmarks del
/// párpado superior que manda MediaPipe) y se extiende hacia la MEJILLA,
/// sobre la zona del parche de hidrogel, con el largo del número que le
/// toca; la curva que une las puntas es la silueta del diseño. Replica el
/// mapeo que la estilista escribe a mano sobre el parche con la clienta
/// acostada — por eso la dirección sale de la anatomía del rostro (ver
/// [_towardCheek]) y no del "abajo" de la imagen: la cabeza puede llegar
/// volcada en cualquier ángulo.
class LashMappingPainter extends CustomPainter {
  /// Igual que `LidLandmarkDebugPainter`: la fuente es un [ValueListenable]
  /// enchufado a `super(repaint:)` para repintar a la cadencia real del
  /// tracking sin pasar por el `setState` throttled de la pantalla.
  final ValueListenable<TrackingFrame?> frames;

  /// `styleId` del diseño activo (ver `_lashStyleIdFor` en
  /// `eye_tracking_page.dart`) — decide qué [_LashMappingPattern] usar.
  final String? styleId;

  const LashMappingPainter({required this.frames, this.styleId})
    : super(repaint: frames);

  /// Misma lógica de transformación usada en el resto del tracking (BoxFit.cover / FILL_CENTER).
  Matrix4? _imageToCanvas(TrackingFrame f, Size canvasSize) {
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
    final f = frames.value;
    if (f == null || !f.faceDetected) return;

    final m = _imageToCanvas(f, size);
    canvas.save();
    if (m != null) canvas.transform(m.storage);

    if (f.leftEye.length >= 4) {
      _drawEyeMapping(canvas, f, f.leftEye, f.leftUpperLid);
    }
    if (f.rightEye.length >= 4) {
      _drawEyeMapping(canvas, f, f.rightEye, f.rightUpperLid);
    }

    canvas.restore();
  }

  void _drawEyeMapping(
    Canvas canvas,
    TrackingFrame frame,
    List<EyePoint> eye,
    List<EyePoint> upperLid,
  ) {
    final pattern = _patternForStyle(styleId);

    // Esquina interna (la más cerca del centro del rostro) y externa. Se
    // resuelve por posición y no por índice: MediaPipe entrega los dos ojos
    // con el anillo recorrido en sentido opuesto.
    final faceCenter = frame.imageWidth / 2.0;
    EyePoint innerPt = eye.first, outerPt = eye.first;
    double minDist = double.infinity, maxDist = -1;
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

    final inner = Offset(innerPt.x, innerPt.y);
    final outer = Offset(outerPt.x, outerPt.y);
    final w = (outer - inner).distance;
    if (w < 5) return;

    // Línea de pestañas, ordenada interna → externa.
    final lashLine = _orderedLashLine(upperLid, inner, outer);

    // Ejes locales del ojo: `axis` recorre interna → externa, `toCheek` es su
    // perpendicular apuntando hacia la mejilla (donde va el parche).
    final axis = (outer - inner) / w;
    final toCheek = _towardCheek(frame, axis);

    // Todo el mapeo vive sobre el parche, corrido del párpado hacia la
    // mejilla (ver [_lashLineOffsetRatio]).
    final patchOffset = toCheek * (w * _lashLineOffsetRatio);
    final patchLine = [for (final p in lashLine) p + patchOffset];

    final numLines = pattern.labels.length;
    final peakIndex = pattern.labels.indexOf(pattern.labels.reduce(math.max));
    final bases = <Offset>[];
    final tips = <Offset>[];
    final dirs = <Offset>[];

    for (int i = 0; i < numLines; i++) {
      final t = i / (numLines - 1);
      final base = _pointAlong(patchLine, t);

      final rawDir = toCheek + axis * (_fanBias * (t - _fanPivotT));
      final dir = rawDir / rawDir.distance;

      final len = pattern.variableLength
          ? w * _maxLineLenRatio * (pattern.labels[i] / _maxMappingLabel)
          : w * _maxLineLenRatio * 0.85;

      bases.add(base);
      dirs.add(dir);
      tips.add(base + dir * len);
    }

    // Línea de base, tenue: deja ver dónde anclan las medidas.
    if (patchLine.length >= 2) {
      canvas.drawPath(
        _smoothPath(patchLine),
        Paint()
          ..color = const Color(0xFFD4AF37).withValues(alpha: 0.55)
          ..strokeWidth = w * 0.012
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // Las líneas del mapeo.
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (int i = 0; i < numLines; i++) {
      final isPeak = i == peakIndex;
      canvas.drawLine(
        bases[i],
        tips[i],
        linePaint
          ..strokeWidth = w * (isPeak ? 0.026 : 0.018)
          ..color = isPeak
              ? const Color(0xFFFFD700).withValues(alpha: 0.95)
              : const Color(0xFFD4AF37).withValues(alpha: 0.85),
      );
    }

    // Curva que une las puntas: es la silueta del diseño (Cat Eye sube hasta
    // la esquina externa; Natural hace pico al centro y vuelve a bajar).
    if (tips.length >= 2) {
      canvas.drawPath(
        _smoothPath(tips),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..strokeWidth = w * 0.014
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // Números, un poco más allá de cada punta. Se dibujan DOS veces: primero
    // un contorno negro y encima el relleno blanco. Con una sombra difusa
    // apenas se leían sobre piel clara, que es el fondo habitual; el
    // contorno los hace legibles sobre cualquier tono.
    final fontSize = w * 0.16;
    for (int i = 0; i < numLines; i++) {
      final label = tips[i] + dirs[i] * (fontSize * 0.75);
      final text = '${pattern.labels[i]}';

      TextPainter painterWith(Paint paint) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            foreground: paint,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final outline = painterWith(
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = fontSize * 0.22
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black.withValues(alpha: 0.85)
          ..isAntiAlias = true,
      );
      final fill = painterWith(
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white
          ..isAntiAlias = true,
      );

      final origin = Offset(
        label.dx - fill.width / 2,
        label.dy - fill.height / 2,
      );
      outline.paint(canvas, origin);
      fill.paint(canvas, origin);
    }
  }

  /// Dirección perpendicular al ojo hacia la que se extiende el mapeo: la
  /// del lado de la MEJILLA, donde se pega el parche y donde la estilista lo
  /// escribe a mano, no hacia la ceja.
  ///
  /// Se deriva del eje mentón→frente del propio rostro (`faceContour[0]` y
  /// `faceContour[18]`, por el orden fijo del óvalo facial de MediaPipe),
  /// NO del "abajo" de la imagen: la clienta trabaja acostada y la estilista
  /// filma desde la cabecera, así que la cabeza llega volcada y un eje
  /// basado en la imagen apuntaría a cualquier lado. Tampoco sirve
  /// `upperLid` vs `lowerLid`: con el ojo cerrado esos dos colapsan y la
  /// dirección se vuelve ruido.
  ///
  /// El sentido es `chin - forehead`, verificado contra capturas del
  /// dispositivo con la clienta acostada: ahí la cabeza llega volcada, el
  /// mentón queda hacia arriba en pantalla y ese vector apunta a la mejilla,
  /// que es donde va el parche. Se probó el opuesto y el mapeo terminaba
  /// sobre las cejas.
  ///
  /// Si no hay contorno facial suficiente, cae a la perpendicular hacia
  /// abajo en la imagen (comportamiento razonable con la cabeza derecha).
  static Offset _towardCheek(TrackingFrame frame, Offset axis) {
    Offset fallback() {
      final perp = Offset(-axis.dy, axis.dx);
      return perp.dy < 0 ? -perp : perp;
    }

    final contour = frame.faceContour;
    if (contour.length < 19) return fallback();

    final forehead = Offset(contour[0].x, contour[0].y);
    final chin = Offset(contour[18].x, contour[18].y);
    final towardCheek = chin - forehead;
    if (towardCheek.distance <= 0) return fallback();

    // Quita la componente paralela al ojo para que quede perpendicular a la
    // línea de pestañas.
    final along = towardCheek.dx * axis.dx + towardCheek.dy * axis.dy;
    final perp = towardCheek - axis * along;
    if (perp.distance < 1e-3) return fallback();
    return perp / perp.distance;
  }

  /// Línea de pestañas (párpado superior), de esquina interna a externa.
  ///
  /// Se probó anclar en el promedio entre párpado superior e inferior,
  /// buscando el borde de cierre del ojo; en dispositivo el abanico quedaba
  /// comprimido en la mitad interna del ojo en vez de recorrerlo entero, así
  /// que se volvió al párpado superior, que es el que cubre todo el ancho.
  ///
  /// El orden viene distinto en cada ojo desde MediaPipe, así que se ordena
  /// por proyección sobre el eje interna→externa en vez de confiar en el
  /// índice del anillo. Sin párpado, la recta entre las dos esquinas.
  static List<Offset> _orderedLashLine(
    List<EyePoint> upperLid,
    Offset inner,
    Offset outer,
  ) {
    if (upperLid.length < 3) return [inner, outer];
    final axis = outer - inner;
    final len2 = axis.distanceSquared;
    if (len2 <= 0) return [inner, outer];

    double projection(Offset p) {
      final d = p - inner;
      return (d.dx * axis.dx + d.dy * axis.dy) / len2;
    }

    return upperLid.map((p) => Offset(p.x, p.y)).toList()
      ..sort((a, b) => projection(a).compareTo(projection(b)));
  }

  /// Punto sobre la polilínea [pts] a la fracción [t] de su largo total.
  static Offset _pointAlong(List<Offset> pts, double t) {
    if (pts.isEmpty) return Offset.zero;
    if (pts.length == 1) return pts.first;

    final segments = <double>[];
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final d = (pts[i + 1] - pts[i]).distance;
      segments.add(d);
      total += d;
    }
    if (total <= 0) return pts.first;

    var target = t.clamp(0.0, 1.0) * total;
    for (int i = 0; i < segments.length; i++) {
      if (target <= segments[i] || i == segments.length - 1) {
        final f = segments[i] <= 0 ? 0.0 : (target / segments[i]).clamp(0.0, 1.0);
        return Offset.lerp(pts[i], pts[i + 1], f)!;
      }
      target -= segments[i];
    }
    return pts.last;
  }

  /// Curva suave (bezier cuadrático por punto medio) a través de una
  /// polilínea abierta, para que no se vea quebrada con pocos puntos.
  static Path _smoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts.last.dx, pts.last.dy);
      return path;
    }
    for (int i = 0; i < pts.length - 1; i++) {
      final mid = Offset.lerp(pts[i], pts[i + 1], 0.5)!;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant LashMappingPainter oldDelegate) =>
      oldDelegate.frames != frames || oldDelegate.styleId != styleId;
}
