import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import 'models/client_dto.dart';

class ClientsApi {
  const ClientsApi(this._dio);

  final Dio _dio;

  Future<List<ClientDto>> list({String? search, int limit = 50}) async {
    final response = await _dio.get<List<dynamic>>(
      ApiEndpoints.clients,
      queryParameters: {
        'skip': 0,
        'limit': limit,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    final data = response.data ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ClientDto.fromJson)
        .toList();
  }
}
