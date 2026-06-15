import 'dart:convert';

import '../config/api_config.dart';
import '../models/client_list_item.dart';
import 'api_client.dart';

/// Lectura de clientes (`GET /api/clients/`) para selección/búsqueda.
class ClientService {
  static Future<List<ClientListItem>> search({
    String? query,
    int limit = 30,
  }) async {
    final body = await ApiClient.get(
      ApiConfig.clients,
      queryParameters: {
        'skip': 0,
        'limit': limit,
        if (query != null && query.trim().isNotEmpty) 'search': query.trim(),
      },
    );

    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Respuesta de clientes inválida');
    }
    return decoded
        .whereType<Map>()
        .map((e) => ClientListItem.fromApi(Map<String, dynamic>.from(e)))
        .toList();
  }
}
