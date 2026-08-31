import 'dart:ui';

class EyePoint {
  final double x;
  final double y;

  const EyePoint({required this.x, required this.y});

  Offset toOffset() => Offset(x, y);

  factory EyePoint.fromMap(Map<dynamic, dynamic> map) {
    return EyePoint(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
    );
  }
}

class TrackingFrame {
  final bool faceDetected;
  /// Resolución del frame que usa MediaPipe (para alinear overlay con el preview).
  final int imageWidth;
  final int imageHeight;
  final List<EyePoint> faceContour;
  final List<EyePoint> leftEye;
  final List<EyePoint> rightEye;
  final EyePoint? leftIris;
  final EyePoint? rightIris;
  final double? leftOpenRatio;
  final double? rightOpenRatio;

  // DEBUG: puntos del anillo completo (16 puntos), separados en
  // párpado superior (8) e inferior (8) para visualización.
  final List<EyePoint> leftUpperLid;
  final List<EyePoint> leftLowerLid;
  final List<EyePoint> rightUpperLid;
  final List<EyePoint> rightLowerLid;

  // Posición REAL de la pestaña detectada por LashEdgeDetector:
  // el píxel más oscuro cerca de cada landmark del párpado superior.
  // Misma cantidad de puntos que upperLid (8). Puede coincidir con
  // upperLid cuando no hay suficiente contraste en la imagen.
  final List<EyePoint> leftLashLine;
  final List<EyePoint> rightLashLine;

  const TrackingFrame({
    required this.faceDetected,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.faceContour = const [],
    required this.leftEye,
    required this.rightEye,
    required this.leftIris,
    required this.rightIris,
    required this.leftOpenRatio,
    required this.rightOpenRatio,
    this.leftUpperLid = const [],
    this.leftLowerLid = const [],
    this.rightUpperLid = const [],
    this.rightLowerLid = const [],
    this.leftLashLine = const [],
    this.rightLashLine = const [],
  });

  factory TrackingFrame.fromMap(Map<dynamic, dynamic> map) {
    List<EyePoint> parseList(dynamic raw) {
      if (raw is! List) return [];
      return raw
          .map((e) => EyePoint.fromMap(Map<dynamic, dynamic>.from(e as Map)))
          .toList();
    }

    EyePoint? parsePoint(dynamic raw) {
      if (raw == null) return null;
      return EyePoint.fromMap(Map<dynamic, dynamic>.from(raw as Map));
    }

    return TrackingFrame(
      faceDetected: map['faceDetected'] == true,
      imageWidth: (map['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (map['imageHeight'] as num?)?.toInt() ?? 0,
      faceContour: parseList(map['faceContour']),
      leftEye: parseList(map['leftEye']),
      rightEye: parseList(map['rightEye']),
      leftIris: parsePoint(map['leftIris']),
      rightIris: parsePoint(map['rightIris']),
      leftOpenRatio: (map['leftOpenRatio'] as num?)?.toDouble(),
      rightOpenRatio: (map['rightOpenRatio'] as num?)?.toDouble(),
      leftUpperLid: parseList(map['leftUpperLid']),
      leftLowerLid: parseList(map['leftLowerLid']),
      rightUpperLid: parseList(map['rightUpperLid']),
      rightLowerLid: parseList(map['rightLowerLid']),
      leftLashLine: parseList(map['leftLashLine']),
      rightLashLine: parseList(map['rightLashLine']),
    );
  }
}