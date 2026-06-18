import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../domain/catalog_repository.dart';
import '../domain/entities/catalog_item.dart';
import 'catalog_api.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._api);

  final CatalogApi _api;

  @override
  Future<List<CatalogItem>> list(CatalogKind kind) async {
    final dtos = await _api.list(kind);
    final items = dtos.map((d) => CatalogItem.fromDto(d, kind)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepositoryImpl(CatalogApi(ref.watch(dioProvider)));
});
