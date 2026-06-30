import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Descarga y cachea localmente archivos de modelos 3D (.glb / .gltf).
///
/// Usa su propio [Dio] sin baseUrl ni interceptores de autenticación:
/// el Dio del backend tiene [responseType] JSON y [AuthInterceptor], que
/// rompen la descarga de archivos binarios desde URLs externas.
class ModelCacheService {
  ModelCacheService(this._dio);

  final Dio _dio;

  /// Devuelve el path absoluto local del modelo 3D identificado por [url].
  ///
  /// - Hit de caché: devuelve el path existente sin hacer petición de red.
  /// - Miss de caché: descarga el archivo y lo guarda antes de devolver el path.
  /// - Error de red o URL inválida: loguea el error y devuelve `null`.
  Future<String?> getModelPath(String url) async {
    final fileName = _fileNameFrom(url);
    if (fileName == null) {
      debugPrint('[ModelCache] URL inválida o sin nombre de archivo: $url');
      return null;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');

      if (await file.exists()) {
        debugPrint('[ModelCache] Cache hit: ${file.path}');
        return file.path;
      }

      debugPrint('[ModelCache] Descargando: $url');
      await _dio
          .download(url, file.path)
          .timeout(const Duration(seconds: 30));
      debugPrint('[ModelCache] Guardado en: ${file.path}');
      return file.path;
    } catch (e, st) {
      debugPrint('[ModelCache] Error al descargar $url\n$e\n$st');
      return null;
    }
  }

  /// Elimina el archivo cacheado para [url], forzando una re-descarga.
  Future<void> evict(String url) async {
    final fileName = _fileNameFrom(url);
    if (fileName == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Extrae el último segmento de la ruta como nombre de archivo.
  String? _fileNameFrom(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    final name = uri.pathSegments.last;
    return name.isNotEmpty ? name : null;
  }
}

/// Dio dedicado para descargas de archivos externos (sin baseUrl, sin auth).
/// No reutiliza [dioProvider] porque ese Dio tiene responseType JSON e
/// interceptores que rompen la descarga de binarios desde URLs externas.
final modelCacheServiceProvider = Provider<ModelCacheService>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
  return ModelCacheService(dio);
});
