import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/prefs_storage.dart';
import 'core/services/notification_service.dart';
import 'native_eye_tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  final prefs = await SharedPreferences.getInstance();

  // Apaga cualquier sesión de cámara que haya quedado viva del lado nativo.
  // En un hot restart el isolate de Dart arranca de cero pero el proceso
  // Android NO muere: `CameraXManager` sobrevive con sus use cases
  // enlazados y sigue analizando frames para siempre, aunque la app esté
  // en el home y ninguna pantalla de cámara exista (visto en logcat:
  // `onPreEngineRestart` destruye las vistas y el manager vuelve a
  // enlazarse solo). No hace nada si no había sesión abierta.
  unawaited(NativeEyeTrackingService().stopTracking());

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const ElashesApp(),
    ),
  );

  // Las notificaciones se inicializan DESPUÉS del primer frame, y sin
  // bloquear el arranque: `NotificationService.init()` termina pidiendo el
  // permiso de Android 13+, y ese diálogo necesita una Activity con UI ya
  // montada. Esperarlo antes de `runApp` trababa la app en el splash para
  // siempre (el splash no se iba porque esperaba el permiso; el permiso no
  // aparecía porque no había UI). No se notaba mientras el permiso ya
  // estuviera concedido — esa llamada retorna al instante —, así que
  // aparecía recién al instalar limpio, que es cuando el permiso se resetea.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      NotificationService.init().catchError((Object e) {
        // Ya no bloquea el arranque, así que un fallo acá no puede quedar
        // como excepción suelta: las notificaciones son accesorias, la app
        // tiene que abrir igual.
        debugPrint('NotificationService.init falló: $e');
      }),
    );
  });
}
