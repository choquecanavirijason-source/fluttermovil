import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../catalogo/data/catalog_repository_impl.dart';
import '../../../catalogo/domain/entities/catalog_item.dart';

/// Carga las cuatro categorías del catálogo en paralelo para construir la
/// recomendación.
final recommendationCatalogProvider = FutureProvider.autoDispose<
    Map<CatalogKind, List<CatalogItem>>>((ref) async {
  final repo = ref.read(catalogRepositoryProvider);
  const kinds = CatalogKind.values;
  final results = await Future.wait(kinds.map(repo.list));
  return {for (var i = 0; i < kinds.length; i++) kinds[i]: results[i]};
});
