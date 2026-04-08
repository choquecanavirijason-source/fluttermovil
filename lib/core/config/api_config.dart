/// Configuración central de la API (mismo esquema que Swagger en `/api/docs`).
class ApiConfig {
  static const String host = 'http://136.115.241.231';
  static const String apiPrefix = '/api';

  /// Rutas relativas al prefijo `/api` (sin duplicar).
  static const String docs = '$apiPrefix/docs';
  static const String authLogin = '$apiPrefix/auth/login';
  static const String authMe = '$apiPrefix/auth/me';
  static const String agendaAppointments = '$apiPrefix/agenda/appointments';
  /// Citas disponibles con al menos un servicio de categoría móvil (`is_mobile=true`).
  static const String agendaAppointmentsMobileAvailable =
      '$apiPrefix/agenda/appointments/mobile/available';
  static const String clients = '$apiPrefix/clients/';
  /// Catálogo de servicios (si el backend lo expone; ver `AgendaService.fetchMobileServices`).
  static const String servicesList = '$apiPrefix/services/';

  /// Sucursal por defecto para filtros de agenda.
  static const int defaultBranchId = 1;

  /// [path] puede ser `auth/login`, `/auth/login` o una ruta ya bajo `/api/`.
  static Uri uri(String path, {Map<String, dynamic>? queryParameters}) {
    String normalized = path.startsWith('/') ? path : '/$path';
    if (!normalized.startsWith(apiPrefix)) {
      normalized = '$apiPrefix$normalized';
    }
    final base = Uri.parse(host);
    final resolved = base.resolve(normalized);
    if (queryParameters == null || queryParameters.isEmpty) {
      return resolved;
    }
    return resolved.replace(
      queryParameters: queryParameters.map(
        (k, v) => MapEntry(k, v?.toString()),
      ),
    );
  }
}
