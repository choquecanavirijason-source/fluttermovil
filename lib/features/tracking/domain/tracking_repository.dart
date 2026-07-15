import 'dart:typed_data';

import 'entities/lash_ai_recommendation.dart';
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

  /// Compara la foto "antes" y "después" de una corrección y devuelve un
  /// consejo que dice qué mejoró y qué falta.
  Future<String> aiCompare({
    required Uint8List beforeJpegBytes,
    required Uint8List afterJpegBytes,
  });

  /// Probador con IA: analiza la foto del ojo y recomienda diseño/efecto/
  /// volumen del catálogo real del salón.
  Future<LashAiRecommendation> aiRecommend(Uint8List jpegBytes);
}
