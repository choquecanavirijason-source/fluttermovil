import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog_repository_impl.dart';
import '../../domain/entities/catalog_item.dart';

/// Lista de modelos de catálogo por tipo.
final catalogListProvider =
    FutureProvider.autoDispose.family<List<CatalogItem>, CatalogKind>(
  (ref, kind) => ref.read(catalogRepositoryProvider).list(kind),
);
