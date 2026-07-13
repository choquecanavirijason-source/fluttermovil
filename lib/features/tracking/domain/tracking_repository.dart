import 'dart:typed_data';

import 'entities/tracking_record.dart';

abstract class TrackingRepository {
  Future<int> create({
    required int clientId,
    int? eyeTypeId,
    int? effectId,
    int? volumeId,
    int? lashDesignId,
    int? branchId,
    String? designNotes,
  });

  /// Historial de aplicaciones del cliente (más reciente primero).
  Future<List<TrackingRecord>> historyByClient(int clientId);

  /// Guiado de IA en vivo (Beauty Tech): envía una foto de la aplicación en
  /// curso y devuelve un consejo breve en texto natural.
  Future<String> aiReview(Uint8List jpegBytes);
}
