import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Envoltorio delgado sobre [FlutterLocalNotificationsPlugin] para mostrar
/// avisos del sistema (bandeja Android/iOS), p. ej. cuando aparece un cliente
/// nuevo sincronizado desde el backend.
class LocalNotificationsService {
  LocalNotificationsService._();

  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  static const String _channelId = 'clientes_nuevos';
  static const String _channelName = 'Clientes nuevos';
  static const String _channelDescription =
      'Avisa cuando se sincroniza un cliente nuevo desde el sistema.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Future en curso de la inicialización; evita que llamadas concurrentes a
  /// [show] disparen antes de que el canal/permiso estén realmente listos
  /// (un simple flag booleano marcado al entrar a [initialize] no alcanza,
  /// porque queda en `true` mientras el trabajo async todavía no terminó).
  Future<void>? _initFuture;

  Future<void> initialize() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.max,
          ));

      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      debugPrint('LocalNotificationsService: permiso Android concedido = $granted');

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('LocalNotificationsService.initialize: $e');
      // Permite reintentar en la próxima llamada a show() en vez de quedar
      // marcado como "inicializado" con un estado roto.
      _initFuture = null;
      rethrow;
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await initialize();
    } catch (_) {
      return;
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      debugPrint('LocalNotificationsService: notificación mostrada (id=$id, "$title")');
    } catch (e) {
      debugPrint('LocalNotificationsService.show: $e');
    }
  }
}

final localNotificationsServiceProvider = Provider<LocalNotificationsService>(
  (ref) => LocalNotificationsService.instance,
);
