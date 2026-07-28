import 'entities/catalog_item.dart';

abstract class CatalogRepository {
  Future<List<CatalogItem>> list(CatalogKind kind);

  /// "Diseños" del admin (`/catalogs/designs`, combos con imagen + modelo
  /// 3D) — entidad distinta a [CatalogKind.lashDesign], que solo mapea
  /// `/catalogs/lash-designs` (nombres sin imagen ni modelo).
  Future<List<CatalogItem>> listDesigns();
}
