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
    this.model3dUrl,
    this.tipoOjoCompatible,
  });

  final int id;
  final String name;
  final CatalogKind kind;
  final String? description;
  final String? imagePath;

  /// URL absoluta al modelo 3D (.glb/.gltf) alojado en el backend.
  final String? model3dUrl;

  /// Clave del tipo de ojo con el que este diseño es compatible (ej. "ALMOND").
  final String? tipoOjoCompatible;

  String? get imageUrl => Env.mediaUrl(imagePath);
  bool get hasImage => imageUrl != null;
  bool get has3dModel => model3dUrl != null && model3dUrl!.isNotEmpty;

  factory CatalogItem.fromDto(CatalogItemDto d, CatalogKind kind) {
    final name = d.name.trim();
    final desc = d.description?.trim();
    return CatalogItem(
      id: d.id,
      name: name.isEmpty ? 'Sin nombre' : name,
      kind: kind,
      description: (desc != null && desc.isNotEmpty) ? desc : null,
      imagePath: d.image,
      model3dUrl: d.model3dUrl,
      tipoOjoCompatible: d.tipoOjoCompatible,
    );
  }

  CatalogItem copyWith({
    int? id,
    String? name,
    CatalogKind? kind,
    String? description,
    String? imagePath,
    String? model3dUrl,
    String? tipoOjoCompatible,
  }) {
    return CatalogItem(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      description: description ?? this.description,
      imagePath: imagePath ?? this.imagePath,
      model3dUrl: model3dUrl ?? this.model3dUrl,
      tipoOjoCompatible: tipoOjoCompatible ?? this.tipoOjoCompatible,
    );
  }
}
