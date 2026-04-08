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
    );
  }
}