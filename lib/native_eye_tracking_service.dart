import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'eye_tracking_model.dart';

class NativeEyeTrackingService {
  /// Singleton — garantiza una única llamada a [receiveBroadcastStream] y un
  /// único handler registrado en el EventChannel nativo, independientemente de
  /// cuántas veces se construya [NativeEyeTrackingService] en el árbol.
  static final NativeEyeTrackingService _instance =
      NativeEyeTrackingService._internal();

  factory NativeEyeTrackingService() => _instance;
  NativeEyeTrackingService._internal();

  static const MethodChannel _methodChannel =
      MethodChannel('eye_tracking/methods');

  static const EventChannel _eventChannel = EventChannel('eye_tracking/events');

  /// Stream broadcast compartido de los mapas raw que envía Kotlin.
  /// Se inicializa al primer acceso (late) y se reutiliza siempre, evitando
  /// registrar múltiples handlers sobre el mismo canal.
  late final Stream<Map<dynamic, dynamic>> _raw = _eventChannel
      .receiveBroadcastStream()
      .map((e) => Map<dynamic, dynamic>.from(e as Map));

  /// Stream completo de frames de tracking (sin cambios en contrato externo).
  Stream<TrackingFrame> get trackingStream => _raw.map(TrackingFrame.fromMap);

  /// Emite la forma de ojo clasificada por Kotlin en tiempo real.
  ///
  /// Valores posibles: 'ALMOND' | 'ROUND' | 'UPTURNED' | 'DOWNTURNED'.
  /// - Omite frames sin cara detectada y valores 'UNKNOWN'.
  /// - Solo emite cuando el valor cambia (distinct) para evitar rebuilds
  ///   innecesarios en los providers que lo escuchan.
  Stream<String> get eyeShapeStream => _raw
      .map((m) => m['leftEyeShape'] as String? ?? '')
      .where((s) => s.isNotEmpty && s != 'UNKNOWN')
      .distinct();

  Future<void> startTracking() async =>
      _methodChannel.invokeMethod('startTracking');

  Future<void> stopTracking() async =>
      _methodChannel.invokeMethod('stopTracking');

  Future<void> switchCamera() async =>
      _methodChannel.invokeMethod('switchCamera');

  /// Fuerza un nuevo bind de CameraX al [PreviewView] (útil al volver del plugin `camera`).
  Future<void> refreshPreviewBind() async {
    try {
      await _methodChannel.invokeMethod('refreshPreviewBind');
    } catch (_) {}
  }

  /// Último frame de cámara como JPEG, ya orientado y espejado igual que el
  /// preview. Necesario porque RepaintBoundary.toImage no puede leer el
  /// PlatformView nativo de CameraX. Devuelve null si aún no hay frame.
  Future<Uint8List?> captureLastCameraFrame() async {
    try {
      return await _methodChannel.invokeMethod<Uint8List>('captureFrame');
    } catch (e) {
      debugPrint('[EyeTracking] captureLastCameraFrame error: $e');
      return null;
    }
  }

  /// Arranca la grabación de video local (sin audio) sobre la misma sesión
  /// de cámara nativa. El archivo se guarda en almacenamiento privado de la app.
  Future<void> startRecording() async {
    await _methodChannel.invokeMethod('startRecording');
  }

  /// Detiene la grabación en curso y devuelve la ruta local del .mp4, o null
  /// si no había ninguna grabación activa.
  Future<String?> stopRecording() async {
    try {
      return await _methodChannel.invokeMethod<String>('stopRecording');
    } catch (e) {
      debugPrint('[EyeTracking] stopRecording error: $e');
      return null;
    }
  }

  /// Envía al lado nativo las rutas locales de los .glb de pestañas para
  /// que Kotlin los cargue en el motor de renderizado (SceneView/Filament),
  /// uno anclado a cada ojo. `null` en cualquiera de los dos deja ese ojo
  /// sin modelo. Llamar varias veces con las mismas rutas es seguro: Kotlin
  /// evita recargar si el modelo ya está cargado.
  Future<void> loadEyeModels({String? leftPath, String? rightPath}) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'loadEyeModels',
        <String, dynamic>{'leftPath': leftPath, 'rightPath': rightPath},
      );
    } on PlatformException catch (e) {
      debugPrint('[EyeTracking] loadEyeModels PlatformException: ${e.code} — ${e.message}');
    } catch (e) {
      // MissingPluginException u otro error inesperado del canal.
      debugPrint('[EyeTracking] loadEyeModels error: $e');
    }
  }
}

/// Provider global del servicio nativo. Al ser singleton, devuelve siempre
/// la misma instancia que usa el widget [EyeTrackingPage].
final nativeEyeTrackingServiceProvider = Provider<NativeEyeTrackingService>(
  (_) => NativeEyeTrackingService(),
);
