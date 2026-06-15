import 'dart:typed_data';

import 'core/recommendation/eye_shape_analyzer.dart';

/// Argumentos para [RecomendacionScreen]: foto capturada de la clienta
/// + análisis on-device de la forma del ojo.
class RecommendationArgs {
  const RecommendationArgs({
    required this.analysis,
    this.photoPngBytes,
    this.mirrorPhoto = false,
  });

  final EyeAnalysis analysis;
  final Uint8List? photoPngBytes;

  /// Espejo horizontal de la foto (coherencia con preview de cámara frontal).
  final bool mirrorPhoto;
}
