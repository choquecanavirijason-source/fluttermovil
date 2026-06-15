import '../config/api_config.dart';

/// Tipo de modelo de catálogo (espejo de la app admin / backend `/api/catalogs`).
enum CatalogKind { lashDesign, eyeType, effect, volume }

extension CatalogKindX on CatalogKind {
  /// Etiqueta en plural para encabezados/pestañas.
  String get label {
    switch (this) {
      case CatalogKind.lashDesign:
        return 'Diseños';
      case CatalogKind.eyeType:
        return 'Tipos de ojo';
      case CatalogKind.effect:
        return 'Efectos';
      case CatalogKind.volume:
        return 'Volúmenes';
    }
  }
}

/// Ítem genérico de catálogo: diseño de pestañas, tipo de ojo, efecto o volumen.
/// Todos comparten `id`, `name` e `image`; algunos traen `description`.
class CatalogModel {
  final int id;
  final String name;
  final String? description;

  /// Ruta de imagen tal como la devuelve el backend (`/media/...`, relativa o absoluta).
  final String? imagePath;
  final CatalogKind kind;

  const CatalogModel({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
    this.imagePath,
  });

  /// URL absoluta lista para `Image.network`, o `null` si no hay imagen.
  String? get imageUrl => ApiConfig.mediaUrl(imagePath);

  bool get hasImage => imageUrl != null;

  factory CatalogModel.fromApi(Map<String, dynamic> m, CatalogKind kind) {
    final desc = m['description']?.toString();
    return CatalogModel(
      id: (m['id'] as num?)?.toInt() ?? 0,
      name: m['name']?.toString().trim().isNotEmpty == true
          ? m['name'].toString().trim()
          : 'Sin nombre',
      kind: kind,
      description: (desc != null && desc.trim().isNotEmpty) ? desc.trim() : null,
      imagePath: m['image']?.toString(),
    );
  }
}
