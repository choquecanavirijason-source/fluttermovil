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
}
