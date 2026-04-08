import 'dart:async';
import 'package:flutter/services.dart';
import 'eye_tracking_model.dart';

class NativeEyeTrackingService {
  static const MethodChannel _methodChannel =
      MethodChannel('eye_tracking/methods');

  static const EventChannel _eventChannel =
      EventChannel('eye_tracking/events');

  Stream<TrackingFrame> get trackingStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return TrackingFrame.fromMap(Map<dynamic, dynamic>.from(event as Map));
    });
  }

  Future<void> startTracking() async {
    await _methodChannel.invokeMethod('startTracking');
  }

  Future<void> stopTracking() async {
    await _methodChannel.invokeMethod('stopTracking');
  }

  Future<void> switchCamera() async {
    await _methodChannel.invokeMethod('switchCamera');
  }

  /// Fuerza un nuevo bind de CameraX al [PreviewView] (útil al volver del plugin `camera`).
  Future<void> refreshPreviewBind() async {
    try {
      await _methodChannel.invokeMethod('refreshPreviewBind');
    } catch (_) {}
  }
}