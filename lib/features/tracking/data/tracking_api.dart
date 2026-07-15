import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';
import '../domain/entities/lash_ai_recommendation.dart';
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

  /// `POST /tracking/ai-review` — guiado de IA en vivo sobre una foto de la
  /// aplicación en curso. Devuelve el consejo en texto natural.
  Future<String> aiReview(Uint8List jpegBytes) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(jpegBytes, filename: 'frame.jpg'),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '${ApiEndpoints.tracking}ai-review',
      data: formData,
    );
    return response.data?['feedback'] as String? ?? '';
  }

  /// `POST /tracking/ai-compare` — compara la foto "antes" y "después" de
  /// una corrección en la misma aplicación. Devuelve el consejo comparativo.
  Future<String> aiCompare({
    required Uint8List beforeJpegBytes,
    required Uint8List afterJpegBytes,
  }) async {
    final formData = FormData.fromMap({
      'before': MultipartFile.fromBytes(beforeJpegBytes, filename: 'before.jpg'),
      'after': MultipartFile.fromBytes(afterJpegBytes, filename: 'after.jpg'),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '${ApiEndpoints.tracking}ai-compare',
      data: formData,
    );
    return response.data?['feedback'] as String? ?? '';
  }

  /// `POST /tracking/ai-recommend` — probador con IA: analiza la foto del
  /// ojo y recomienda diseño/efecto/volumen del catálogo real del salón.
  Future<LashAiRecommendation> aiRecommend(Uint8List jpegBytes) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(jpegBytes, filename: 'eye.jpg'),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '${ApiEndpoints.tracking}ai-recommend',
      data: formData,
    );
    return LashAiRecommendation.fromJson(response.data ?? const {});
  }
}
