import '../../../core/recommendation/eye_shape_analyzer.dart';
import '../../catalogo/domain/entities/catalog_item.dart';
import 'lash_recommendation.dart';

/// Motor de recomendación por reglas: mapea cada forma de ojo a nombres de
/// diseños/efectos/volúmenes y los empareja con el catálogo real.
class LashRecommender {
  static const Map<EyeShape, List<String>> _designsByShape = {
    EyeShape.almendrado: ['Cat Eye', 'Natural', 'Wispy'],
    EyeShape.encapotado: ['Cat Eye', 'Squirrel', 'Wispy'],
    EyeShape.redondo: ['Cat Eye', 'Squirrel', 'Wispy'],
    EyeShape.rasgado: ['Doll', 'Wispy', 'Natural'],
    EyeShape.asimetricos: ['Wispy', 'Natural', 'Cat Eye'],
  };

  static const Map<EyeShape, List<String>> _effectsByShape = {
    EyeShape.almendrado: ['Foxy Eye', 'Natural'],
    EyeShape.encapotado: ['Foxy Eye', 'Kim K'],
    EyeShape.redondo: ['Foxy Eye', 'Kim K'],
    EyeShape.rasgado: ['Doll Eye', 'Wet Look'],
    EyeShape.asimetricos: ['Natural', 'Doll Eye'],
  };

  static const Map<EyeShape, List<String>> _volumesByShape = {
    EyeShape.almendrado: ['2D', '3D'],
    EyeShape.encapotado: ['2D', '3D'],
    EyeShape.redondo: ['3D', '5D'],
    EyeShape.rasgado: ['Clásico', '2D'],
    EyeShape.asimetricos: ['2D', 'Clásico'],
  };

  static const Map<EyeShape, String> _reasonByShape = {
    EyeShape.almendrado:
        'Tu mirada es equilibrada: casi cualquier estilo te queda. Sugerimos diseños versátiles que realzan sin recargar.',
    EyeShape.encapotado:
        'Para el párpado caído conviene elevar el extremo externo: diseños tipo cat eye/squirrel abren y levantan la mirada.',
    EyeShape.redondo:
        'Para alargar un ojo redondo recomendamos diseños que estiran el extremo externo (cat eye / squirrel).',
    EyeShape.rasgado:
        'Para abrir y redondear un ojo alargado funcionan los diseños doll/wispy, con volumen contenido al centro.',
    EyeShape.asimetricos:
        'Detectamos diferencia entre ambos ojos: estilos wispy/natural ayudan a equilibrar visualmente la mirada.',
  };

  static LashRecommendation build({
    required EyeAnalysis analysis,
    required List<CatalogItem> eyeTypes,
    required List<CatalogItem> designs,
    required List<CatalogItem> effects,
    required List<CatalogItem> volumes,
  }) {
    final shape = analysis.shape;
    return LashRecommendation(
      shape: shape,
      eyeType: _matchOne(eyeTypes, shape.catalogName),
      designs: _matchMany(designs, _designsByShape[shape] ?? const []),
      effects: _matchMany(effects, _effectsByShape[shape] ?? const []),
      volumes: _matchMany(volumes, _volumesByShape[shape] ?? const []),
      reason: _reasonByShape[shape] ?? '',
    );
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();

  static CatalogItem? _matchOne(List<CatalogItem> pool, String name) {
    final target = _normalize(name);
    for (final m in pool) {
      final n = _normalize(m.name);
      if (n == target || n.contains(target) || target.contains(n)) return m;
    }
    return null;
  }

  static List<CatalogItem> _matchMany(
    List<CatalogItem> pool,
    List<String> wanted,
  ) {
    final out = <CatalogItem>[];
    final used = <int>{};
    for (final w in wanted) {
      final target = _normalize(w);
      for (final m in pool) {
        if (used.contains(m.id)) continue;
        final n = _normalize(m.name);
        if (n == target || n.contains(target) || target.contains(n)) {
          out.add(m);
          used.add(m.id);
          break;
        }
      }
    }
    if (out.isEmpty && pool.isNotEmpty) return pool.take(3).toList();
    return out;
  }
}
