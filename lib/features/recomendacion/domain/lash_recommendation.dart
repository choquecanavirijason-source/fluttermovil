import '../../../core/recommendation/eye_shape_analyzer.dart';
import '../../catalogo/domain/entities/catalog_item.dart';

/// Recomendación de catálogo derivada de la forma del ojo.
class LashRecommendation {
  const LashRecommendation({
    required this.shape,
    required this.eyeType,
    required this.designs,
    required this.effects,
    required this.volumes,
    required this.reason,
  });

  final EyeShape shape;
  final CatalogItem? eyeType;
  final List<CatalogItem> designs;
  final List<CatalogItem> effects;
  final List<CatalogItem> volumes;
  final String reason;

  bool get hasAnyItem =>
      eyeType != null ||
      designs.isNotEmpty ||
      effects.isNotEmpty ||
      volumes.isNotEmpty;
}
