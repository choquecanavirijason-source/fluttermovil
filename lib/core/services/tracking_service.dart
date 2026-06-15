import 'dart:convert';

import '../config/api_config.dart';
import 'api_client.dart';

/// Crea registros de seguimiento (ficha del cliente) en `POST /api/tracking/`.
/// La operaria tiene el permiso `tracking:manage`.
class TrackingService {
  /// Devuelve el `id` del seguimiento creado.
  static Future<int> create({
    required int clientId,
    int? eyeTypeId,
    int? effectId,
    int? volumeId,
    int? lashDesignId,
    int? branchId,
    String? designNotes,
  }) async {
    final body = <String, dynamic>{
      'client_id': clientId,
      'eye_type_id': ?eyeTypeId,
      'effect_id': ?effectId,
      'volume_id': ?volumeId,
      'lash_design_id': ?lashDesignId,
      'branch_id': ?branchId,
      'design_notes':
          ?(designNotes != null && designNotes.trim().isNotEmpty
              ? designNotes.trim()
              : null),
    };

    final text = await ApiClient.post(ApiConfig.tracking, body: body);
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['id'] is num) {
      return (decoded['id'] as num).toInt();
    }
    return 0;
  }
}
