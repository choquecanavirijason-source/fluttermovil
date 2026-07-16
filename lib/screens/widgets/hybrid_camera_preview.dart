import 'dart:io';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Preview de cámara con **Hybrid Composition** (`initExpensiveAndroidView`).
/// Necesario para que el vídeo de CameraX (TextureView) se renderice; con
/// `AndroidView` simple el preview salía negro aunque el análisis sí corría.
///
/// Compartido entre [EyeTrackingPage] y [WorkAssistantScreen]: ambas
/// pantallas apuntan al mismo `CameraXManager` nativo (una única sesión de
/// cámara), así que basta con recrear este widget con una `key` distinta
/// para forzar un rebind al entrar/salir de cada pantalla.
///
/// [leftModelPath]/[rightModelPath] (rutas de archivo a los `.glb` de
/// pestañas) viajan como `creationParams` del `PlatformView`: Kotlin los
/// recibe en el mismo `create()` que instancia el `SceneView` y carga el
/// modelo ahí mismo, de forma síncrona — así la recreación de este
/// `PlatformView` (al volver a la pantalla, o al forzar una nueva `key`)
/// nunca depende de un segundo viaje Dart→Kotlin por `MethodChannel` con
/// delays. Pasar `null` en cualquiera de los dos dejar ese ojo sin modelo.
class HybridCameraPreview extends StatelessWidget {
  const HybridCameraPreview({
    super.key,
    this.leftModelPath,
    this.rightModelPath,
  });

  final String? leftModelPath;
  final String? rightModelPath;

  static const String _viewType = 'eye_tracking/camera_preview';

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: <String, dynamic>{
            'leftModelPath': leftModelPath,
            'rightModelPath': rightModelPath,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
        return controller;
      },
    );
  }
}

/// Modelo de pestañas por defecto mientras no exista selección dinámica por
/// diseño del catálogo (ver `ESTADO_ACTUAL.md`, sección 2 — "calibración
/// pendiente"). Es el mismo modelo que hoy muestra el probador.
const String defaultLeftEyeModelAsset = 'assets/modelos/cateye/cateyeleft.glb';
const String defaultRightEyeModelAsset =
    'assets/modelos/cateye/cateyeright.glb';

/// Copia un asset de Flutter (bundle) a un archivo local: `SceneView` solo
/// carga `.glb` desde una ruta de archivo real, no desde el asset bundle.
Future<String> extractEyeModelAssetToFile(String assetPath) async {
  final byteData = await rootBundle.load(assetPath);
  final bytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${assetPath.split('/').last}');
  if (!await file.exists() || await file.length() != bytes.length) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return file.path;
}
