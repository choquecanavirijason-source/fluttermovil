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
const _catEyePattern = _LashMappingPattern([
  9,
  10,
  11,
  12,
  13,
  14,
], variableLength: true);
const _naturalPattern = _LashMappingPattern([
  9,
  10,
  11,
  12,
  11,
  10,
], variableLength: true);

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
/// Referencia: en un teléfono típico el ojo mide ~58 px lógicos, así que
/// 0.1 ≈ 6 px. Va siempre hacia la MEJILLA (anatómico, ver [_towardCheek]).
///
/// Historial 2026-09-30: 0.16 → 0 (base sobre la línea de pestañas) → 0.2
/// (quedaba en el pliegue) → 0.1 → 0.05, punto medio entre 0 y 0.1 validado
/// en dispositivo con la clienta de frente. Este es el número a mover si
/// queda muy encima de la pestaña o demasiado separado — y SOLO ese: si el
/// mapeo aparece del lado de las cejas, eso no se arregla acá (ver
/// `CameraXManager.analysisRotated180`).
const _lashLineOffsetRatio = 0.1;

/// Tamaño de los números, como fracción del ancho del ojo.
const _labelFontRatio = 0.16;

/// TEMPORAL — log de orientación (filtrar por `OrientDebug`). Borrar junto
/// con `OrientDebug.kt` cuando quede confirmado.
const _kOrientDebug = true;

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

/// Geometría ya resuelta del mapeo de UN ojo, en coordenadas de la imagen
/// (ver [LashMappingPainter.layoutFor]). Todas las listas van de la comisura
/// INTERNA a la EXTERNA, en el orden de [labels].
@visibleForTesting
class EyeMappingLayout {
  final List<int> labels;
  final int peakIndex;
  final double eyeWidth;
  final List<Offset> patchLine;
  final List<Offset> bases;
  final List<Offset> tips;
  final List<Offset> labelCenters;

  /// Giro de los números, en radianes, siempre dentro de (−π/2, π/2].
  final double labelAngle;

  const EyeMappingLayout({
    required this.labels,
    required this.peakIndex,
    required this.eyeWidth,
    required this.patchLine,
    required this.bases,
    required this.tips,
    required this.labelCenters,
    required this.labelAngle,
  });
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
  final Offset leftEyeOffset;
  final Offset rightEyeOffset;

  const LashMappingPainter({
    required this.frames,
    this.styleId,
    this.leftEyeOffset = Offset.zero,
    this.rightEyeOffset = Offset.zero,
  }) : super(repaint: frames);

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

    final layouts = layoutFor(
      f,
      styleId: styleId,
      leftEyeOffset: leftEyeOffset,
      rightEyeOffset: rightEyeOffset,
    );
    if (layouts.isEmpty) return;

    final m = _imageToCanvas(f, size);
    canvas.save();
    if (m != null) canvas.transform(m.storage);
    for (final layout in layouts) {
      _drawEyeMapping(canvas, layout);
    }
    canvas.restore();
  }

  /// `true` si el ojo `leftEye` de MediaPipe es el que SE VE a la izquierda
  /// de la pantalla. Con la cara derecha lo es; con la clienta echada (cara
  /// invertida) queda a la derecha. Los controles de ajuste manual lo usan
  /// para que el panel de cada lado mueva la grilla de ese lado.
  static bool leftEyeIsOnScreenLeft(TrackingFrame f) {
    if (f.leftEye.isEmpty || f.rightEye.isEmpty) return true;
    return _centroid(f.leftEye).dx <= _centroid(f.rightEye).dx;
  }

  /// Franja vertical (`top`, `bottom`) que ocupa el mapeo dibujado —líneas,
  /// curva y números— en un canvas de [canvasSize], con el mismo encuadre
  /// `BoxFit.cover` que [paint]. `null` si no hay nada que dibujar. Sirve
  /// para ubicar los controles de ajuste sin taparlo.
  static ({double top, double bottom})? verticalExtentOnCanvas(
    TrackingFrame f,
    Size canvasSize, {
    String? styleId,
    Offset leftEyeOffset = Offset.zero,
    Offset rightEyeOffset = Offset.zero,
  }) {
    final iw = f.imageWidth.toDouble();
    final ih = f.imageHeight.toDouble();
    if (iw <= 0 || ih <= 0) return null;
    final layouts = layoutFor(
      f,
      styleId: styleId,
      leftEyeOffset: leftEyeOffset,
      rightEyeOffset: rightEyeOffset,
    );
    if (layouts.isEmpty) return null;
    final scale = math.max(canvasSize.width / iw, canvasSize.height / ih);
    final dy = (canvasSize.height - ih * scale) / 2;
    var top = double.infinity, bottom = -double.infinity;
    for (final l in layouts) {
      // Medio alto de número de margen, para no rozar las etiquetas.
      final margin = l.eyeWidth * _labelFontRatio * 0.6;
      for (final p in [...l.bases, ...l.tips, ...l.labelCenters]) {
        top = math.min(top, (p.dy - margin) * scale + dy);
        bottom = math.max(bottom, (p.dy + margin) * scale + dy);
      }
    }
    return (top: top, bottom: bottom);
  }

  /// Geometría del mapeo de cada ojo, en coordenadas de la IMAGEN (las de
  /// [TrackingFrame]), sin dibujar nada. Separada de [paint] para poder
  /// probar las orientaciones del rostro sin canvas.
  ///
  /// Todo se calcula en el sistema de coordenadas del ROSTRO, no de la
  /// pantalla: el eje "derecha" del rostro es el vector entre los centros de
  /// los dos ojos, y el ojo de cada lado sale de su identidad anatómica en
  /// MediaPipe (`leftEye` = índices 33/133…, `rightEye` = 362/263…), que no
  /// cambia aunque la cabeza llegue de costado o dada vuelta. Así el mapeo
  /// queda igual con la clienta acostada a 90°, −90° o 180°.
  @visibleForTesting
  static List<EyeMappingLayout> layoutFor(
    TrackingFrame f, {
    String? styleId,
    Offset leftEyeOffset = Offset.zero,
    Offset rightEyeOffset = Offset.zero,
  }) {
    final hasLeft = f.leftEye.length >= 4;
    final hasRight = f.rightEye.length >= 4;
    final leftCenter = hasLeft ? _centroid(f.leftEye) + leftEyeOffset : null;
    final rightCenter = hasRight
        ? _centroid(f.rightEye) + rightEyeOffset
        : null;

    // Ejes del rostro. `faceDown` (hacia el mentón) es la perpendicular
    // del eje entre ojos; con y hacia abajo, (−dy, dx) da (0, 1) con la cara
    // derecha. Sin los dos ojos no hay eje y se cae al de la imagen.
    Offset? faceDown;
    var labelAngle = 0.0;
    if (leftCenter != null && rightCenter != null) {
      final across = rightCenter - leftCenter;
      if (across.distance > 1e-3) {
        final faceRight = across / across.distance;
        faceDown = Offset(-faceRight.dy, faceRight.dx);
        labelAngle = _readableAngle(math.atan2(faceRight.dy, faceRight.dx));
      }
    }

    final pattern = _patternForStyle(styleId);
    return [
      if (hasLeft)
        ?_layoutEye(
          f,
          pattern,
          f.leftEye,
          f.leftUpperLid,
          leftEyeOffset,
          otherEyeCenter: rightCenter,
          faceDown: faceDown,
          labelAngle: labelAngle,
        ),
      if (hasRight)
        ?_layoutEye(
          f,
          pattern,
          f.rightEye,
          f.rightUpperLid,
          rightEyeOffset,
          otherEyeCenter: leftCenter,
          faceDown: faceDown,
          labelAngle: labelAngle,
        ),
    ];
  }

  static EyeMappingLayout? _layoutEye(
    TrackingFrame frame,
    _LashMappingPattern pattern,
    List<EyePoint> eye,
    List<EyePoint> upperLid,
    Offset eyeOffset, {
    required Offset? otherEyeCenter,
    required Offset? faceDown,
    required double labelAngle,
  }) {
    List<EyePoint> shifted(List<EyePoint> points) => [
      for (final point in points)
        EyePoint(x: point.x + eyeOffset.dx, y: point.y + eyeOffset.dy),
    ];

    eye = shifted(eye);
    upperLid = shifted(upperLid);

    // Esquina interna (la más cerca del OTRO OJO, o sea de la nariz) y
    // externa (la más lejana). Se resuelve por posición y no por índice:
    // MediaPipe entrega los dos ojos con el anillo recorrido en sentido
    // opuesto. Antes se medía contra el centro HORIZONTAL de la imagen, que
    // con el rostro de costado deja los dos ojos a la misma distancia y
    // elegía esquinas al azar (y con la cara corrida a un lado, las
    // invertía). Sin el otro ojo, se mantiene ese criterio de respaldo.
    double distToNose(EyePoint p) => otherEyeCenter == null
        ? (p.x - frame.imageWidth / 2.0).abs()
        : (Offset(p.x, p.y) - otherEyeCenter).distance;
    EyePoint innerPt = eye.first, outerPt = eye.first;
    double minDist = double.infinity, maxDist = -1;
    for (final p in eye) {
      final d = distToNose(p);
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
    if (w < 5) return null;

    // Línea de pestañas, ordenada interna → externa.
    final lashLine = _orderedLashLine(upperLid, inner, outer);

    // Ejes locales del ojo: `axis` recorre interna → externa, `toCheek` es su
    // perpendicular apuntando hacia la mejilla (donde va el parche).
    final axis = (outer - inner) / w;
    //
    // Antes había un parámetro `towardForehead` que invertía esta dirección
    // para las fotos tomadas en modo invertido. Era una SEGUNDA corrección:
    // en ese modo MediaPipe analiza el frame rotado (ve la cara derecha) y
    // los landmarks llegan ya desrotados al espacio de la foto, con la
    // identidad anatómica intacta, así que frente→mentón ya apunta a la
    // mejilla. Invertirla mandaba la grilla a las cejas.
    final toCheek = _towardCheek(frame, axis, faceDown);
    if (_kOrientDebug) {
      final c = frame.faceContour;
      final foreheadToChin = c.length >= 19
          ? Offset(c[18].x - c[0].x, c[18].y - c[0].y)
          : null;
      debugPrint(
        'OrientDebug grilla interna=$inner externa=$outer '
        'frente→mentón=$foreheadToChin faceDown=$faceDown toCheek=$toCheek',
      );
    }

    // Todo el mapeo vive sobre el parche, corrido del párpado hacia la
    // mejilla (ver [_lashLineOffsetRatio]).
    final patchOffset = toCheek * (w * _lashLineOffsetRatio);
    final patchLine = [for (final p in lashLine) p + patchOffset];

    final numLines = pattern.labels.length;
    final peakIndex = pattern.labels.indexOf(pattern.labels.reduce(math.max));
    final bases = <Offset>[];
    final tips = <Offset>[];
    final labelCenters = <Offset>[];
    final fontSize = w * _labelFontRatio;

    for (int i = 0; i < numLines; i++) {
      final t = i / (numLines - 1);
      final base = _pointAlong(patchLine, t);
      // 1 px hacia la frente del rostro (con la cara derecha, lo mismo que
      // el `dy - 1` de pantalla que había antes).
      final adjustedBase = base - toCheek;

      final rawDir = toCheek + axis * (_fanBias * (t - _fanPivotT));
      final dir = rawDir / rawDir.distance;

      final len = pattern.variableLength
          ? w * _maxLineLenRatio * (pattern.labels[i] / _maxMappingLabel)
          : w * _maxLineLenRatio * 0.85;

      final tip = adjustedBase + dir * len;
      bases.add(adjustedBase);
      tips.add(tip);
      labelCenters.add(tip + dir * (fontSize * 0.75));
    }

    return EyeMappingLayout(
      labels: pattern.labels,
      peakIndex: peakIndex,
      eyeWidth: w,
      patchLine: patchLine,
      bases: bases,
      tips: tips,
      labelCenters: labelCenters,
      labelAngle: labelAngle,
    );
  }

  void _drawEyeMapping(Canvas canvas, EyeMappingLayout layout) {
    final w = layout.eyeWidth;
    final patchLine = layout.patchLine;
    final bases = layout.bases;
    final tips = layout.tips;
    final numLines = layout.labels.length;
    final peakIndex = layout.peakIndex;

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
    //
    // Cada número se gira con el rostro ([EyeMappingLayout.labelAngle]),
    // acotado para que nunca quede cabeza abajo en pantalla.
    final fontSize = w * _labelFontRatio;
    for (int i = 0; i < numLines; i++) {
      final label = layout.labelCenters[i];
      final text = '${layout.labels[i]}';

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

      final origin = Offset(-fill.width / 2, -fill.height / 2);
      canvas.save();
      canvas.translate(label.dx, label.dy);
      if (layout.labelAngle != 0) canvas.rotate(layout.labelAngle);
      outline.paint(canvas, origin);
      fill.paint(canvas, origin);
      canvas.restore();
    }
  }

  static Offset _centroid(List<EyePoint> points) {
    var x = 0.0, y = 0.0;
    for (final p in points) {
      x += p.x;
      y += p.y;
    }
    return Offset(x / points.length, y / points.length);
  }

  /// Ángulo del texto a partir del ángulo del eje entre ojos, llevado a
  /// (−90°, 90°]: con el rostro a 180° el número queda derecho en pantalla
  /// en vez de cabeza abajo, y a ±90° se lee de costado.
  static double _readableAngle(double angle) {
    if (angle > math.pi / 2) return angle - math.pi;
    if (angle <= -math.pi / 2) return angle + math.pi;
    return angle;
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
  /// Si no hay contorno facial suficiente, cae a la perpendicular del lado
  /// de [faceDown] (hacia el mentón según el eje entre ojos) y, sin eso,
  /// a la de abajo en la imagen (razonable sólo con la cabeza derecha).
  static Offset _towardCheek(
    TrackingFrame frame,
    Offset axis,
    Offset? faceDown,
  ) {
    Offset fallback() {
      final perp = Offset(-axis.dy, axis.dx);
      final down = faceDown ?? const Offset(0, 1);
      return perp.dx * down.dx + perp.dy * down.dy < 0 ? -perp : perp;
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
        final f = segments[i] <= 0
            ? 0.0
            : (target / segments[i]).clamp(0.0, 1.0);
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
      oldDelegate.frames != frames ||
      oldDelegate.styleId != styleId ||
      oldDelegate.leftEyeOffset != leftEyeOffset ||
      oldDelegate.rightEyeOffset != rightEyeOffset;
}
