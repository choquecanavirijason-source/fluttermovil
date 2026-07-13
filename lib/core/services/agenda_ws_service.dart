import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';
import '../storage/secure_storage.dart';
import '../../features/auth/domain/entities/auth_user.dart';
import '../../features/auth/presentation/providers/auth_state_provider.dart';

/// Evento de agenda emitido por el backend vía WebSocket
/// (`app/core/ws_manager.py` → `/ws/branch/{branch_id}`, broadcast por `branch_id`).
class AgendaWsEvent {
  const AgendaWsEvent({
    required this.event,
    this.ticketId,
    this.professionalId,
    this.status,
  });

  /// `ticket_created` | `ticket_called` | `ticket_updated` | `ticket_deleted`.
  final String event;
  final int? ticketId;
  final int? professionalId;
  final String? status;

  factory AgendaWsEvent.fromJson(Map<String, dynamic> json) {
    return AgendaWsEvent(
      event: json['event']?.toString() ?? '',
      ticketId: (json['ticket_id'] as num?)?.toInt(),
      professionalId: (json['professional_id'] as num?)?.toInt(),
      status: json['status']?.toString(),
    );
  }
}

/// Conexión WebSocket persistente a `/ws/branch/{branchId}` para recibir
/// eventos de agenda (citas creadas/actualizadas/llamadas/eliminadas) en
/// tiempo real, en vez de tener que sondear la API periódicamente.
///
/// El servidor transmite por `branch_id` (no filtra por profesional), así
/// que el filtrado por `professional_id` lo hace quien consuma [events].
/// Se reconecta solo si la conexión se corta.
class AgendaWsService {
  AgendaWsService(this._ref);

  final Ref _ref;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _stopped = true;

  final StreamController<AgendaWsEvent> _eventsController =
      StreamController<AgendaWsEvent>.broadcast();

  /// Emite cada evento de agenda recibido del backend.
  Stream<AgendaWsEvent> get events => _eventsController.stream;

  static const Duration _reconnectDelay = Duration(seconds: 5);

  Future<void> connect() async {
    _stopped = false;
    await _connectOnce();
  }

  Future<void> _connectOnce() async {
    if (_stopped) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final token = await _ref.read(secureStorageProvider).readToken();
    if (token == null || token.isEmpty) {
      // Sin sesión todavía; reintenta más tarde en vez de quedar sin conexión.
      _scheduleReconnect();
      return;
    }

    final AuthUser? user = _ref.read(authUserProvider);
    final branchId = user?.branchId;
    if (branchId == null) {
      // Sin sucursal asignada todavía (p. ej. justo tras el login); reintenta.
      _scheduleReconnect();
      return;
    }

    // Se conecta directo al backend (puerto `Env.wsDirectPort`), sin pasar
    // por nginx: nginx en producción todavía no reenvía `/ws/` (solo
    // `/api/`), así que ir por el puerto 80 devuelve el HTML de la SPA en
    // vez de hacer el upgrade a websocket. El REST sigue usando nginx
    // (`Env.apiBaseUrl`) sin cambios; esto solo afecta esta conexión.
    final httpUri = Uri.parse(Env.host);
    final uri = Uri(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      host: httpUri.host,
      port: Env.wsDirectPort,
      path: '/ws/branch/$branchId',
      queryParameters: {'token': token},
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (_stopped) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onError: (Object e, StackTrace st) {
          debugPrint('AgendaWsService: error de socket: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('AgendaWsService: socket cerrado');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
      debugPrint('AgendaWsService: conectado a $uri');
    } catch (e) {
      debugPrint('AgendaWsService: falló la conexión: $e');
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = AgendaWsEvent.fromJson(decoded);
      debugPrint('AgendaWsService: evento recibido -> ${event.event} '
          'ticket=${event.ticketId} profesional=${event.professionalId}');
      _eventsController.add(event);
    } catch (e) {
      debugPrint('AgendaWsService: mensaje inválido: $e');
    }
  }

  void _scheduleReconnect() {
    unawaited(_sub?.cancel());
    _sub = null;
    _channel = null;
    if (_stopped) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () => unawaited(_connectOnce()));
  }

  /// Fuerza una reconexión inmediata (p. ej. al volver del background,
  /// donde el sistema operativo pudo haber cortado el socket).
  void reconnectNow() {
    if (_stopped) return;
    unawaited(_connectOnce());
  }

  Future<void> disconnect() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }
}

final agendaWsServiceProvider = Provider<AgendaWsService>((ref) {
  final service = AgendaWsService(ref);
  ref.onDispose(() => unawaited(service.disconnect()));
  return service;
});

/// Expone [AgendaWsService.events] como provider para que otras pantallas
/// (ej. "Mi comisión") puedan reaccionar en vivo sin manejar su propia
/// suscripción/lifecycle — el stream es *broadcast*, así que puede tener
/// varios oyentes a la vez sin pisarse.
final agendaWsEventsProvider = StreamProvider<AgendaWsEvent>((ref) {
  return ref.watch(agendaWsServiceProvider).events;
});
