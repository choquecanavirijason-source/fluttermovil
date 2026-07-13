import 'dart:math' as math;

import '../../eye_tracking_model.dart';

/// Formas de ojo reconocidas (espejo del catálogo `eye_types` del backend:
/// Almendrado, Encapotado, Redondo, Rasgado, Asimétricos).
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

  const _EyeMetrics({
    required this.aspectRatio,
    required this.tiltDeg,
    required this.openness,
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
}

/// Clasifica la forma del ojo usando solo la geometría de los landmarks.
/// 100% on-device, sin internet ni costo.
class EyeShapeAnalyzer {
  /// Umbrales heurísticos (ajustables tras pruebas en dispositivo).
  static const double _roundMaxAspect = 2.6; // por debajo → redondo (alto)
  static const double _longMinAspect = 3.6; // por encima → rasgado (alargado)
  static const double _hoodedTiltDeg = -6.0; // caída marcada → encapotado
  static const double _asymmetryThreshold = 0.32;

  static EyeAnalysis analyze(TrackingFrame? frame) {
    if (frame == null || !frame.faceDetected) return EyeAnalysis.none;
    if (frame.leftEye.length < 4 || frame.rightEye.length < 4) {
      return EyeAnalysis.none;
    }

    // Centro aproximado del rostro: punto medio entre los centroides de ambos ojos.
    final lc = _centroid(frame.leftEye);
    final rc = _centroid(frame.rightEye);
    final faceMidX = (lc.dx + rc.dx) / 2.0;

    final left = _metricsFor(frame.leftEye, faceMidX);
    final right = _metricsFor(frame.rightEye, faceMidX);
    if (left == null || right == null) return EyeAnalysis.none;

    final aspect = (left.aspectRatio + right.aspectRatio) / 2.0;
    final tilt = (left.tiltDeg + right.tiltDeg) / 2.0;
    final openness = (left.openness + right.openness) / 2.0;

    final asymmetry = aspect <= 0
        ? 0.0
        : (left.aspectRatio - right.aspectRatio).abs() / aspect;

    final shape = _classify(
      aspect: aspect,
      tilt: tilt,
      asymmetry: asymmetry,
    );

    return EyeAnalysis(
      shape: shape,
      aspectRatio: aspect,
      canthalTiltDeg: tilt,
      openness: openness,
      asymmetry: asymmetry,
      reliable: true,
      leftTiltDeg: left.tiltDeg,
      rightTiltDeg: right.tiltDeg,
    );
  }

  static EyeShape _classify({
    required double aspect,
    required double tilt,
    required double asymmetry,
  }) {
    if (asymmetry > _asymmetryThreshold) return EyeShape.asimetricos;
    if (tilt <= _hoodedTiltDeg) return EyeShape.encapotado;
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

    final width = (cornerMaxX.x - cornerMinX.x).abs();
    final height = (maxY - minY).abs();
    if (width < 1.0 || height < 0.5) return null;

    // Interna = esquina más cercana al centro del rostro.
    final innerIsMaxX = (cornerMaxX.x - faceMidX).abs() <
        (cornerMinX.x - faceMidX).abs();
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

class _Pt {
  final double dx;
  final double dy;
  const _Pt(this.dx, this.dy);
}
