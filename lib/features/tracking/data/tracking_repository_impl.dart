import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../domain/entities/tracking_record.dart';
import '../domain/tracking_repository.dart';
import 'tracking_api.dart';

class TrackingRepositoryImpl implements TrackingRepository {
  TrackingRepositoryImpl(this._api);

  final TrackingApi _api;

  @override
  Future<int> create({
    required int clientId,
    int? eyeTypeId,
    int? effectId,
    int? volumeId,
    int? lashDesignId,
    int? branchId,
    String? designNotes,
  }) {
    final notes = designNotes?.trim();
    final body = <String, dynamic>{
      'client_id': clientId,
      'eye_type_id': ?eyeTypeId,
      'effect_id': ?effectId,
      'volume_id': ?volumeId,
      'lash_design_id': ?lashDesignId,
      'branch_id': ?branchId,
      'design_notes': ?(notes != null && notes.isNotEmpty ? notes : null),
    };
    return _api.create(body);
  }

  @override
  Future<List<TrackingRecord>> historyByClient(int clientId) async {
    final dtos = await _api.listByClient(clientId);
    final records = dtos.map(TrackingRecord.fromDto).toList()
      ..sort((a, b) {
        final da = a.date, db = b.date;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    return records;
  }
}

final trackingRepositoryProvider = Provider<TrackingRepository>((ref) {
  return TrackingRepositoryImpl(TrackingApi(ref.watch(dioProvider)));
});
