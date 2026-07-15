import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

/// Preview de cámara con **Hybrid Composition** (`initExpensiveAndroidView`).
/// Necesario para que el vídeo de CameraX (TextureView) se renderice; con
/// `AndroidView` simple el preview salía negro aunque el análisis sí corría.
///
/// Compartido entre [EyeTrackingPage] y [WorkAssistantScreen]: ambas
/// pantallas apuntan al mismo `CameraXManager` nativo (una única sesión de
/// cámara), así que basta con recrear este widget con una `key` distinta
/// para forzar un rebind al entrar/salir de cada pantalla.
class HybridCameraPreview extends StatelessWidget {
  const HybridCameraPreview({super.key});

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
