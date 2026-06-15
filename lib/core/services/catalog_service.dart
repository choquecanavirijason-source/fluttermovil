import 'dart:convert';

import '../config/api_config.dart';
import '../models/catalog_model.dart';
import 'api_client.dart';

/// Lee los modelos de catálogo (`/api/catalogs/...`) que la operaria puede ver
/// (`catalog:view`). Son los mismos modelos que administra la app admin.
class CatalogService {
  static const Map<CatalogKind, String> _endpoints = {
    CatalogKind.lashDesign: ApiConfig.catalogLashDesigns,
    CatalogKind.eyeType: ApiConfig.catalogEyeTypes,
    CatalogKind.effect: ApiConfig.catalogEffects,
    CatalogKind.volume: ApiConfig.catalogVolumes,
  };

  static Future<List<CatalogModel>> fetch(CatalogKind kind) async {
    final endpoint = _endpoints[kind]!;
    final body = await ApiClient.get(
      endpoint,
      queryParameters: {'skip': 0, 'limit': 200},
    );

    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Respuesta de catálogo inválida');
    }

    final list = decoded
        .whereType<Map>()
        .map((e) => CatalogModel.fromApi(Map<String, dynamic>.from(e), kind))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Diseños de pestañas (lo más usado en el flujo de la operaria).
  static Future<List<CatalogModel>> fetchLashDesigns() =>
      fetch(CatalogKind.lashDesign);

  /// Carga las cuatro categorías en paralelo.
  static Future<Map<CatalogKind, List<CatalogModel>>> fetchAll() async {
    final kinds = CatalogKind.values;
    final results = await Future.wait(kinds.map(fetch));
    return {for (var i = 0; i < kinds.length; i++) kinds[i]: results[i]};
  }
}
