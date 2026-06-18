import 'entities/catalog_item.dart';

abstract class CatalogRepository {
  Future<List<CatalogItem>> list(CatalogKind kind);
}
