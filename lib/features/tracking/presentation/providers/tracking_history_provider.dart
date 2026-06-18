import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/tracking_repository_impl.dart';
import '../../domain/entities/tracking_record.dart';

/// Historial de aplicaciones de un cliente.
final clientTrackingProvider =
    FutureProvider.autoDispose.family<List<TrackingRecord>, int>(
  (ref, clientId) =>
      ref.read(trackingRepositoryProvider).historyByClient(clientId),
);
