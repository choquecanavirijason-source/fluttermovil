import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import 'models/tracking_dto.dart';

class TrackingApi {
  const TrackingApi(this._dio);

  final Dio _dio;

  /// `POST /tracking/` — registra el seguimiento (ficha) del cliente.
  /// Devuelve el `id` creado.
  Future<int> create(Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.tracking,
      data: body,
    );
    final id = response.data?['id'];
    return id is num ? id.toInt() : 0;
  }

  /// `GET /tracking/?client_id=X` — historial de aplicaciones del cliente.
  Future<List<TrackingDto>> listByClient(int clientId, {int limit = 50}) async {
    final response = await _dio.get<List<dynamic>>(
      ApiEndpoints.tracking,
      queryParameters: {'client_id': clientId, 'skip': 0, 'limit': limit},
    );
    final data = response.data ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(TrackingDto.fromJson)
        .toList();
  }
}
