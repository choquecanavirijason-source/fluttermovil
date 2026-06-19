import '../../../../core/config/env.dart';
import '../../data/models/catalog_item_dto.dart';

/// Tipo de modelo de catálogo (espejo de `/api/catalogs/...`).
/// El orden y los nombres coinciden con el menú "Diseño Pestañas" del admin
/// para mantener consistencia entre apps.
enum CatalogKind { effect, eyeType, volume, lashDesign }

extension CatalogKindX on CatalogKind {
  String get label => switch (this) {
        CatalogKind.effect => 'Efectos',
        CatalogKind.eyeType => 'Tipo de ojo',
        CatalogKind.volume => 'Volumen',
        CatalogKind.lashDesign => 'Diseños',
      };
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
    this.imagePath,
  });

  final int id;
  final String name;
  final CatalogKind kind;
  final String? description;
  final String? imagePath;

  String? get imageUrl => Env.mediaUrl(imagePath);
  bool get hasImage => imageUrl != null;

  factory CatalogItem.fromDto(CatalogItemDto d, CatalogKind kind) {
    final name = d.name.trim();
    final desc = d.description?.trim();
    return CatalogItem(
      id: d.id,
      name: name.isEmpty ? 'Sin nombre' : name,
      kind: kind,
      description: (desc != null && desc.isNotEmpty) ? desc : null,
      imagePath: d.image,
    );
  }
}
