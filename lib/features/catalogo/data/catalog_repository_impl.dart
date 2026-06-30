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

    // ─────────────────────────────────────────────────────────────────────────
    // TODO: REMOVE MOCK 3D DATA
    // Inyección temporal para probar el flujo 3D antes de que el backend esté
    // listo. Eliminar este bloque cuando la API devuelva 'model_3d_url' y
    // 'tipo_ojo_compatible' en los endpoints de catálogo.
    // ─────────────────────────────────────────────────────────────────────────
    final itemsWithMock = items
        .map(
          (item) => item.copyWith(
            model3dUrl:
                'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models'
                '/master/2.0/Box/glTF-Binary/Box.glb',
            tipoOjoCompatible: 'almendrado',
          ),
        )
        .toList();
    // ─────────────────────────────────────────────────────────────────────────

    return itemsWithMock;
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepositoryImpl(CatalogApi(ref.watch(dioProvider)));
});
