import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'elashes_tickets';
const _channelName = 'Turnos Elashes';

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings: initSettings);

    // Canal de alta prioridad para Android 8+
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Notificaciones de turnos de atención en tiempo real',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Solicitar permiso en Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  static Future<void> showFromEvent(Map<String, dynamic> event) async {
    if (!_initialized) return;

    final type = event['event'] as String?;
    final ticketId = event['ticket_id'] as int? ?? 0;

    String title;
    String body;

    switch (type) {
      case 'ticket_created':
        title = 'Nuevo turno';
        body = 'Se agregó un nuevo cliente a la cola';
      case 'ticket_called':
        title = 'Turno llamado';
        body = 'Un cliente está siendo llamado';
      case 'ticket_updated':
        title = 'Turno actualizado';
        body = 'El estado de un turno cambió';
      default:
        return; // ticket_deleted no necesita notificación
    }

    await _plugin.show(
      id: ticketId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }
}
