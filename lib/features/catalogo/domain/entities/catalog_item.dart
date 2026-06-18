import '../../../../core/config/env.dart';
import '../../data/models/catalog_item_dto.dart';

/// Tipo de modelo de catálogo (espejo de `/api/catalogs/...`).
enum CatalogKind { lashDesign, eyeType, effect, volume }

extension CatalogKindX on CatalogKind {
  String get label => switch (this) {
        CatalogKind.lashDesign => 'Diseños',
        CatalogKind.eyeType => 'Tipos de ojo',
        CatalogKind.effect => 'Efectos',
        CatalogKind.volume => 'Volúmenes',
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
