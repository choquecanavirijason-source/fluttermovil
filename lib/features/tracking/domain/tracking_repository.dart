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
}
