import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import '../domain/entities/catalog_item.dart';
import 'models/catalog_item_dto.dart';

class CatalogApi {
  const CatalogApi(this._dio);

  final Dio _dio;

  static String _endpoint(CatalogKind kind) => switch (kind) {
        CatalogKind.lashDesign => ApiEndpoints.catalogLashDesigns,
        CatalogKind.eyeType => ApiEndpoints.catalogEyeTypes,
        CatalogKind.effect => ApiEndpoints.catalogEffects,
        CatalogKind.volume => ApiEndpoints.catalogVolumes,
      };

  Future<List<CatalogItemDto>> list(CatalogKind kind) async {
    final response = await _dio.get<List<dynamic>>(
      _endpoint(kind),
      queryParameters: {'skip': 0, 'limit': 200},
    );
    final data = response.data ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(CatalogItemDto.fromJson)
        .toList();
  }

  /// "Diseños" (`/catalogs/designs`): el response no tiene
  /// `tipo_ojo_compatible` (ese campo no existe en esta entidad, es
  /// exclusivo del catálogo genérico), así que se reusa `eye_type` (texto
  /// libre elegido al crear el diseño) con el mismo propósito de filtrado.
  Future<List<CatalogItemDto>> listDesigns() async {
    final response = await _dio.get<List<dynamic>>(
      ApiEndpoints.catalogDesigns,
      queryParameters: {'skip': 0, 'limit': 200},
    );
    final data = response.data ?? const [];
    return data.whereType<Map<String, dynamic>>().map((json) {
      final mapped = Map<String, dynamic>.from(json);
      mapped['tipo_ojo_compatible'] = json['eye_type'];
      return CatalogItemDto.fromJson(mapped);
    }).toList();
  }
}
