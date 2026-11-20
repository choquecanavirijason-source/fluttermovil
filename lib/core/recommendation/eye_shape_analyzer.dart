import 'dart:math' as math;

import '../../eye_tracking_model.dart';

/// Legacy values remain readable. Automatic classification uses contour shape;
/// tilt and asymmetry are separate measurements, not eyelid diagnoses.
enum EyeShape { almendrado, encapotado, redondo, rasgado, asimetricos }

extension EyeShapeX on EyeShape {
  /// Nombre tal como aparece en el catálogo (para emparejar con `eye_types`).
  String get catalogName {
    switch (this) {
      case EyeShape.almendrado:
        return 'Almendrado';
      case EyeShape.encapotado:
        return 'Encapotado';
      case EyeShape.redondo:
        return 'Redondo';
      case EyeShape.rasgado:
        return 'Rasgado';
      case EyeShape.asimetricos:
        return 'Asimétricos';
    }
  }

  String get description {
    switch (this) {
      case EyeShape.almendrado:
        return 'Forma equilibrada y versátil; admite casi cualquier estilo.';
      case EyeShape.encapotado:
        return 'Párpado superior con ligera caída; conviene elevar la mirada.';
      case EyeShape.redondo:
        return 'Apertura ocular amplia; favorece alargar el ojo.';
      case EyeShape.rasgado:
        return 'Ojo alargado; favorece abrir y redondear la mirada.';
      case EyeShape.asimetricos:
        return 'Un ojo difiere del otro; conviene equilibrar el diseño.';
    }
  }
}

/// Métricas geométricas de un ojo, normalizadas por su ancho.
class _EyeMetrics {
  final double aspectRatio; // ancho / alto
  final double tiltDeg; // + = elevado (foxy), - = caído
  final double openness; // alto / ancho
  final double width, innerX, innerY;

  const _EyeMetrics({
    required this.aspectRatio,
    required this.tiltDeg,
    required this.openness,
    required this.width,
    required this.innerX,
    required this.innerY,
  });
}

/// Resultado del análisis de la forma del ojo a partir de un [TrackingFrame].
class EyeAnalysis {
  final EyeShape shape;
  final double aspectRatio;
  final double canthalTiltDeg;
  final double openness;
  final double asymmetry; // 0..1, diferencia relativa entre ambos ojos
  final bool reliable;
  final double separationRatio;
  final double widthDifference;
  final double leftAspectRatio, rightAspectRatio;

  /// Tilt (elevación) de cada ojo por separado — útil para detectar que un
  /// lado quedó más caído/elevado que el otro durante la aplicación.
  final double leftTiltDeg;
  final double rightTiltDeg;

  const EyeAnalysis({
    required this.shape,
    required this.aspectRatio,
    required this.canthalTiltDeg,
    required this.openness,
    required this.asymmetry,
    required this.reliable,
    this.leftTiltDeg = 0,
    this.rightTiltDeg = 0,
    this.separationRatio = 1,
    this.widthDifference = 0,
    this.leftAspectRatio = 0,
    this.rightAspectRatio = 0,
  });

  /// Análisis vacío cuando no hay rostro/landmarks suficientes.
  static const EyeAnalysis none = EyeAnalysis(
    shape: EyeShape.almendrado,
    aspectRatio: 0,
    canthalTiltDeg: 0,
    openness: 0,
    asymmetry: 0,
    reliable: false,
  );

  String get summary {
    if (!reliable) {
      return 'No se detectó el rostro con claridad. Centra la mirada e inténtalo de nuevo.';
    }
    final tilt = canthalTiltDeg >= 4
        ? 'mirada elevada'
        : canthalTiltDeg <= -4
        ? 'mirada con caída'
        : 'mirada neutra';
    return 'Forma ${shape.catalogName.toLowerCase()} · $tilt.';
  }

  String get separationLabel => separationRatio < .85
      ? 'Cercanos'
      : separationRatio > 1.15
      ? 'Separados'
      : 'Equilibrados';
  String get inclinationLabel => canthalTiltDeg >= 4
      ? 'Ascendente'
      : canthalTiltDeg <= -4
      ? 'Descendente'
      : 'Neutra';
  String get symmetryLabel =>
      asymmetry > .15 ? 'Diferencia de apertura' : 'Apertura equilibrada';
}

/// Clasifica la forma del ojo usando solo la geometría de los landmarks.
/// 100% on-device, sin internet ni costo.
class EyeShapeAnalyzer {
  /// Umbrales heurísticos (ajustables tras pruebas en dispositivo).
  static const double _roundMaxAspect = 2.6; // por debajo → redondo (alto)
  static const double _longMinAspect = 3.6; // por encima → rasgado (alargado)

  static EyeAnalysis analyze(TrackingFrame? frame) {
    if (frame == null || !frame.faceDetected) return EyeAnalysis.none;
    if (frame.leftEye.length < 4 || frame.rightEye.length < 4) {
      return EyeAnalysis.none;
    }

    // Las métricas de abajo (ancho = x, alto = y, "arriba" = y menor) asumen
    // el rostro derecho. Con la clienta acostada llega de costado o dado
    // vuelta, así que primero se pasan los puntos a ejes del ROSTRO: x a lo
    // largo del vector entre ojos (identidad anatómica de MediaPipe, no
    // posición en pantalla) e y hacia el mentón, con origen entre los ojos.
    final lc = _centroid(frame.leftEye);
    final rc = _centroid(frame.rightEye);
    final acrossX = rc.dx - lc.dx;
    final acrossY = rc.dy - lc.dy;
    final across = math.sqrt(acrossX * acrossX + acrossY * acrossY);
    if (across < 1.0) return EyeAnalysis.none;
    // Eje derecha del rostro (ux, uy); el de abajo es su perpendicular
    // (−uy, ux), que con la cara derecha da (0, 1).
    final ux = acrossX / across;
    final uy = acrossY / across;
    final midX = (lc.dx + rc.dx) / 2.0;
    final midY = (lc.dy + rc.dy) / 2.0;
    List<EyePoint> toFace(List<EyePoint> eye) => [
      for (final p in eye)
        EyePoint(
          x: (p.x - midX) * ux + (p.y - midY) * uy,
          y: -(p.x - midX) * uy + (p.y - midY) * ux,
        ),
    ];
    const faceMidX = 0.0;

    final left = _metricsFor(toFace(frame.leftEye), faceMidX);
    final right = _metricsFor(toFace(frame.rightEye), faceMidX);
    if (left == null || right == null) return EyeAnalysis.none;

    final aspect = (left.aspectRatio + right.aspectRatio) / 2.0;
    final tilt = (left.tiltDeg + right.tiltDeg) / 2.0;
    final openness = (left.openness + right.openness) / 2.0;

    final asymmetry = aspect <= 0
        ? 0.0
        : (left.aspectRatio - right.aspectRatio).abs() / aspect;

    final shape = _classify(aspect: aspect, tilt: tilt, asymmetry: asymmetry);

    return EyeAnalysis(
      shape: shape,
      aspectRatio: aspect,
      canthalTiltDeg: tilt,
      openness: openness,
      asymmetry: asymmetry,
      reliable: true,
      leftTiltDeg: left.tiltDeg,
      rightTiltDeg: right.tiltDeg,
      separationRatio:
          math.sqrt(
            math.pow(left.innerX - right.innerX, 2) +
                math.pow(left.innerY - right.innerY, 2),
          ) /
          ((left.width + right.width) / 2),
      widthDifference:
          (left.width - right.width).abs() / ((left.width + right.width) / 2),
      leftAspectRatio: left.aspectRatio,
      rightAspectRatio: right.aspectRatio,
    );
  }

  static EyeShape _classify({
    required double aspect,
    required double tilt,
    required double asymmetry,
  }) {
    if (aspect < _roundMaxAspect) return EyeShape.redondo;
    if (aspect > _longMinAspect) return EyeShape.rasgado;
    return EyeShape.almendrado;
  }

  /// Calcula métricas de un ojo. [faceMidX] sirve para distinguir
  /// esquina interna (cercana a la nariz) de la externa, de forma robusta al espejo.
  static _EyeMetrics? _metricsFor(List<EyePoint> eye, double faceMidX) {
    if (eye.length < 4) return null;

    // Esquinas = puntos con x mínima y máxima.
    EyePoint cornerMinX = eye.first;
    EyePoint cornerMaxX = eye.first;
    double minY = eye.first.y;
    double maxY = eye.first.y;
    for (final p in eye) {
      if (p.x < cornerMinX.x) cornerMinX = p;
      if (p.x > cornerMaxX.x) cornerMaxX = p;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    // Measure the contour in this eye's own axes. A slanted corner-to-corner
    // line must not artificially increase height and change the shape label.
    final axisX = cornerMaxX.x - cornerMinX.x;
    final axisY = cornerMaxX.y - cornerMinX.y;
    final width = math.sqrt(axisX * axisX + axisY * axisY);
    if (width < 1.0) return null;
    final perpendicularX = -axisY / width;
    final perpendicularY = axisX / width;
    minY = double.infinity;
    maxY = double.negativeInfinity;
    for (final p in eye) {
      final projected =
          (p.x - cornerMinX.x) * perpendicularX +
          (p.y - cornerMinX.y) * perpendicularY;
      minY = math.min(minY, projected);
      maxY = math.max(maxY, projected);
    }
    final height = maxY - minY;
    if (height < 0.5) return null;

    // Interna = esquina más cercana al centro del rostro.
    final innerIsMaxX =
        (cornerMaxX.x - faceMidX).abs() < (cornerMinX.x - faceMidX).abs();
    final inner = innerIsMaxX ? cornerMaxX : cornerMinX;
    final outer = innerIsMaxX ? cornerMinX : cornerMaxX;

    // y crece hacia abajo: externa por encima de la interna → mirada elevada (+).
    final dy = inner.y - outer.y;
    final dx = (outer.x - inner.x).abs().clamp(1.0, double.infinity);
    final tiltDeg = math.atan2(dy, dx) * 180.0 / math.pi;

    return _EyeMetrics(
      aspectRatio: width / height,
      tiltDeg: tiltDeg,
      openness: height / width,
      width: width,
      innerX: inner.x,
      innerY: inner.y,
    );
  }

  static _Pt _centroid(List<EyePoint> pts) {
    double sx = 0, sy = 0;
    for (final p in pts) {
      sx += p.x;
      sy += p.y;
    }
    return _Pt(sx / pts.length, sy / pts.length);
  }
}

/// Collects open-eye readings before locking a session result. Blinks and
/// missing faces do not become new eye shapes. No camera/render state changes.
class SessionEyeAnalysis {
  final List<({DateTime at, EyeAnalysis value})> _samples = [];
  EyeAnalysis? result;
  bool needsAdjustment = false;

  void reset() {
    _samples.clear();
    result = null;
    needsAdjustment = false;
  }

  EyeAnalysis? add(TrackingFrame frame, DateTime now) {
    if (result != null) return result;
    if (!frame.faceDetected) {
      _samples.clear();
      needsAdjustment = true;
      return null;
    }
    final value = EyeShapeAnalyzer.analyze(frame);
    if (!value.reliable ||
        value.openness < .10 ||
        value.openness > .65 ||
        value.widthDifference > .30 ||
        value.separationRatio < .3 ||
        value.separationRatio > 2.5) {
      needsAdjustment = true;
      return null;
    }
    if (_samples.isNotEmpty &&
        now.difference(_samples.last.at).inMilliseconds < 100) {
      return null;
    }
    _samples.removeWhere(
      (s) => now.difference(s.at) > const Duration(seconds: 3),
    );
    _samples.add((at: now, value: value));
    if (_samples.length < 12 ||
        now.difference(_samples.first.at).inMilliseconds < 2800) {
      needsAdjustment = false;
      return null;
    }
    double median(double Function(EyeAnalysis) read) {
      final values = _samples.map((s) => read(s.value)).toList()..sort();
      final middle = values.length ~/ 2;
      return values.length.isOdd
          ? values[middle]
          : (values[middle - 1] + values[middle]) / 2;
    }

    final aspect = median((a) => a.aspectRatio);
    final tilt = median((a) => a.canthalTiltDeg);
    if (median((a) => (a.aspectRatio - aspect).abs()) > .25 ||
        median((a) => (a.canthalTiltDeg - tilt).abs()) > 3 ||
        (aspect - 2.6).abs() < .06 ||
        (aspect - 3.6).abs() < .06) {
      needsAdjustment = true;
      return null;
    }
    result = EyeAnalysis(
      shape: EyeShapeAnalyzer._classify(
        aspect: aspect,
        tilt: tilt,
        asymmetry: 0,
      ),
      aspectRatio: aspect,
      canthalTiltDeg: tilt,
      openness: median((a) => a.openness),
      asymmetry: median((a) => a.asymmetry),
      reliable: true,
      leftTiltDeg: median((a) => a.leftTiltDeg),
      rightTiltDeg: median((a) => a.rightTiltDeg),
      separationRatio: median((a) => a.separationRatio),
      widthDifference: median((a) => a.widthDifference),
      leftAspectRatio: median((a) => a.leftAspectRatio),
      rightAspectRatio: median((a) => a.rightAspectRatio),
    );
    needsAdjustment = false;
    return result;
  }
}

class _Pt {
  final double dx;
  final double dy;
  const _Pt(this.dx, this.dy);
}
