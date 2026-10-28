import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Interruptor del diagnóstico de frames de Flutter ([FlutterTimingsDiag]).
/// `false` lo apaga por completo: no registra el callback ni el timer.
// ignore: constant_identifier_names
const bool PERF_DIAG = true;

/// DIAGNÓSTICO de rendimiento: agrega los [FrameTiming] del motor de Flutter
/// y cada [_window] emite una línea `FLUTTER_TIMINGS` (logcat, tag `flutter`,
/// también en release) con cuántos frames hubo, cuántos pasaron de un
/// período de 60 Hz en build (hilo UI) o en raster (hilo raster), y los
/// máximos.
///
/// Sirve para saber si los `frames_largos` que mide Kotlin en el hilo
/// principal de Android vienen de Flutter o de otra parte. Solo observa: no
/// cambia nada del árbol de widgets.
class FlutterTimingsDiag {
  FlutterTimingsDiag({this.label = ''});

  /// Contexto opcional que se agrega a la línea (p. ej. `overlays=off`).
  String label;

  static const Duration _window = Duration(seconds: 2);
  static const int _budgetMicros = 16700;

  Timer? _timer;
  int _frames = 0;
  int _slowBuild = 0;
  int _slowRaster = 0;
  int _maxBuildMicros = 0;
  int _maxRasterMicros = 0;

  void start() {
    if (!PERF_DIAG || _timer != null) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Timer y no "cada N frames": una ventana sin frames también es un dato
    // (Flutter quieto mientras la cámara corre).
    _timer = Timer.periodic(_window, (_) => _flush());
  }

  void stop() {
    if (_timer == null) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    _timer = null;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds;
      final raster = t.rasterDuration.inMicroseconds;
      _frames++;
      if (build > _budgetMicros) _slowBuild++;
      if (raster > _budgetMicros) _slowRaster++;
      if (build > _maxBuildMicros) _maxBuildMicros = build;
      if (raster > _maxRasterMicros) _maxRasterMicros = raster;
    }
  }

  void _flush() {
    String ms(int micros) => (micros / 1000).toStringAsFixed(1);
    debugPrint(
      'FLUTTER_TIMINGS ${label.isEmpty ? '' : '$label '}'
      'ventana=${_window.inSeconds}s frames=$_frames '
      'build>16.7ms=$_slowBuild raster>16.7ms=$_slowRaster '
      'max_build=${ms(_maxBuildMicros)}ms max_raster=${ms(_maxRasterMicros)}ms',
    );
    _frames = 0;
    _slowBuild = 0;
    _slowRaster = 0;
    _maxBuildMicros = 0;
    _maxRasterMicros = 0;
  }
}
