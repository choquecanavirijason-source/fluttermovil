import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/env.dart';

typedef WsEventHandler = void Function(Map<String, dynamic> event);

/// Servicio WebSocket para recibir eventos en tiempo real del backend.
/// Uso: llamar [connect] al entrar a la pantalla y [dispose] al salir.
class WsService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final int branchId;
  final WsEventHandler onEvent;

  WsService({required this.branchId, required this.onEvent});

  static Uri _wsUri(int branchId) {
    final base = Env.host
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    return Uri.parse('$base/ws/branch/$branchId');
  }

  void connect() {
    if (_disposed) return;
    try {
      _channel = WebSocketChannel.connect(_wsUri(branchId));
      _sub = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            onEvent(data);
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }
}
