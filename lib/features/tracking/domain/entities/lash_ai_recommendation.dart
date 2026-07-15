/// Recomendación real de IA (visión) para el probador: la IA mira la foto
/// del ojo de la clienta y elige, del catálogo real del salón, el
/// diseño/efecto/volumen que mejor le queda. Complementa (no reemplaza) a
/// `LashRecommender`, que es una heurística on-device por geometría.
class LashAiRecommendation {
  const LashAiRecommendation({
    required this.reason,
    this.eyeShape,
    this.recommendedDesign,
    this.recommendedEffect,
    this.recommendedVolume,
    required this.model,
  });

  final String reason;
  final String? eyeShape;
  final String? recommendedDesign;
  final String? recommendedEffect;
  final String? recommendedVolume;
  final String model;

  factory LashAiRecommendation.fromJson(Map<String, dynamic> json) {
    return LashAiRecommendation(
      reason: json['reason'] as String? ?? '',
      eyeShape: json['eye_shape'] as String?,
      recommendedDesign: json['recommended_design'] as String?,
      recommendedEffect: json['recommended_effect'] as String?,
      recommendedVolume: json['recommended_volume'] as String?,
      model: json['model'] as String? ?? '',
    );
  }
}
