import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.errors,
    this.isUnauthorized = false,
    this.isNetwork = false,
  });

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? errors;
  final bool isUnauthorized;
  final bool isNetwork;

  @override
  String toString() => 'ApiException($statusCode): $message';

  /// Mensaje para el usuario cuando la IA está desactivada en el salón.
  static const aiDisabledUserMessage =
      'Por favor activa la función de IA en la configuración para recibir '
      'consejos.';

  /// El backend responde 400 "Activa la IA en configuración" cuando la
  /// función de IA está apagada. La app no tiene copia local de ese ajuste
  /// (vive en el servidor), así que esta respuesta es la única señal.
  bool get isAiDisabled =>
      statusCode == 400 &&
      message.toLowerCase().contains('activa la ia');

  /// Extrae el [ApiException] de cualquier error de la capa de red: el
  /// `ErrorInterceptor` lo deja dentro de `DioException.error`.
  static ApiException? from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final inner = error.error;
      if (inner is ApiException) return inner;
      return ApiException.fromDio(error);
    }
    return null;
  }

  /// Texto apto para mostrar al usuario, sin "DioException"/"ApiException(400)".
  static String userMessage(Object error, {required String fallback}) {
    final api = from(error);
    if (api == null) return fallback;
    if (api.isAiDisabled) return aiDisabledUserMessage;
    if (api.isNetwork) return api.message;
    return api.message.trim().isNotEmpty ? api.message : fallback;
  }

  factory ApiException.fromDio(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const ApiException(
        message: 'Sin conexión a internet',
        isNetwork: true,
      );
    }

    final response = error.response;
    final status = response?.statusCode;
    final data = response?.data;

    var message = error.message ?? 'Error desconocido';
    Map<String, dynamic>? fieldErrors;

    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List) {
        message = detail.map(_formatValidationItem).join('\n');
      } else if (detail is Map<String, dynamic>) {
        fieldErrors = detail;
        message = detail.values.first?.toString() ?? message;
      }
    } else if (data is String && data.isNotEmpty) {
      message = data;
    }

    return ApiException(
      message: message,
      statusCode: status,
      errors: fieldErrors,
      isUnauthorized: status == 401,
    );
  }

  static String _formatValidationItem(dynamic item) {
    if (item is Map<String, dynamic>) {
      final msg = item['msg']?.toString() ?? '';
      final loc = item['loc'];
      if (loc is List && loc.isNotEmpty) {
        return '${loc.join('.')}: $msg';
      }
      return msg;
    }
    return item.toString();
  }
}
