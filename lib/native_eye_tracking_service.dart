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

  /// Alterna entre cámara frontal y trasera. Devuelve `true` si quedó en la
  /// frontal — Kotlin (`CameraXManager.lensFacing`) es la única fuente de
  /// verdad de este estado; Flutter no debe llevar su propia copia porque el
  /// manager nativo sobrevive a la recreación de las pantallas y hay dos que
  /// ofrecen cambiar de cámara. `null` si el manager todavía no existe.
  Future<bool?> switchCamera() async =>
      _methodChannel.invokeMethod<bool>('switchCamera');

  /// Modo "clienta acostada": el frame se rota 180° antes del análisis, así
  /// MediaPipe ve una cara derecha y la ajusta bien.
  ///
  /// Se activa SOLO dentro del asistente de mapeo, por dos motivos. Uno: con
  /// el análisis rotado el modelo 3D de pestañas se ubica mal, porque lee
  /// los landmarks crudos por otro camino y no recibe la corrección que sí
  /// recibe el overlay de Flutter (en el asistente no molesta, ahí el modelo
  /// está oculto). Dos: fuera del asistente el rostro viene derecho, y
  /// rotarlo lo volvería indetectable.
  Future<void> setInvertedFaceMode(bool enabled) async {
    try {
      await _methodChannel.invokeMethod<void>('setInvertedFaceMode', {
        'enabled': enabled,
      });
    } catch (e) {
      debugPrint('[EyeTracking] setInvertedFaceMode error: $e');
    }
  }

  /// Saca una foto (JPEG) por la MISMA sesión de cámara que está
  /// analizando, sin detener el tracking ni abrir otra cámara.
  ///
  /// Es lo que permite que la foto del asistente salga casi del mismo
  /// instante que el mapeo dibujado encima: abrir una segunda sesión metía
  /// 1-2 s en el medio y, con el pulso de la mano, el mapeo quedaba corrido
  /// respecto del ojo. Solo funciona con [setInvertedFaceMode] activo, que
  /// es cuando se enlaza el caso de uso de foto. `null` si no está
  /// disponible — ahí el llamador debe caer al camino viejo.
  Future<Uint8List?> takePhoto() async {
    try {
      return await _methodChannel.invokeMethod<Uint8List>('takePhoto');
    } catch (e) {
      debugPrint('[EyeTracking] takePhoto error: $e');
      return null;
    }
  }

  /// Consulta a Kotlin qué cámara está activa ahora mismo (ver
  /// [switchCamera]). `null` si el manager nativo todavía no está creado.
  Future<bool?> isUsingFrontCamera() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isUsingFrontCamera');
    } catch (_) {
      return null;
    }
  }

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
  /// Relanza cualquier error del canal (antes se tragaba silenciosamente con
  /// solo un debugPrint) — el llamador (ver `_switchDesignModel` en
  /// EyeTrackingPage) necesita enterarse si el cambio de modelo falló para
  /// poder avisarle a la usuaria, en vez de fallar en silencio y que parezca
  /// que "el diseño no cambia".
  Future<void> loadEyeModels({String? leftPath, String? rightPath}) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'loadEyeModels',
        <String, dynamic>{'leftPath': leftPath, 'rightPath': rightPath},
      );
    } on PlatformException catch (e) {
      debugPrint('[EyeTracking] loadEyeModels PlatformException: ${e.code} — ${e.message}');
      rethrow;
    } catch (e) {
      // MissingPluginException u otro error inesperado del canal.
      debugPrint('[EyeTracking] loadEyeModels error: $e');
      rethrow;
    }
  }

  /// Informa a Kotlin qué `LashStyleConfig` usar (ver
  /// `render/LashStyleConfig.kt`) para el diseño que se acaba de cargar con
  /// [loadEyeModels] — heightOffset/noseAvoidShift/envolvente en Z varían
  /// por estilo artístico (Cat Eye, Natural, Wispy...), no son calibración
  /// fija del motor. `styleId` desconocido/no registrado en Kotlin cae a un
  /// estilo neutro (`LashStyleConfig.DEFAULT`) en vez de fallar — no hace
  /// falta `rethrow` acá como en [loadEyeModels]: un estilo sin ajuste fino
  /// no es un error bloqueante, el modelo se sigue viendo (solo sin el
  /// ajuste particular de ese diseño), a diferencia de que el `.glb` en sí
  /// no cargue.
  Future<void> setLashStyle(String? styleId) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setLashStyle',
        <String, dynamic>{'styleId': styleId},
      );
    } catch (e) {
      debugPrint('[EyeTracking] setLashStyle error: $e');
    }
  }
}

/// Provider global del servicio nativo. Al ser singleton, devuelve siempre
/// la misma instancia que usa el widget [EyeTrackingPage].
final nativeEyeTrackingServiceProvider = Provider<NativeEyeTrackingService>(
  (_) => NativeEyeTrackingService(),
);
