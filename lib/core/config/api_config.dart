/// Configuración central de la API (mismo esquema que Swagger en `/api/docs`).
class ApiConfig {
  static const String host = 'http://34.55.150.142';
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
  /// Seguimiento por cliente (ficha): diseño/efecto/volumen aplicados.
  static const String tracking = '$apiPrefix/tracking/';
  /// Cierre diario: citas + comisión por profesional y fecha.
  static const String reportsDailyClosing = '$apiPrefix/reports/daily-closing';
  /// Catálogo de servicios.
  static const String servicesList = '$apiPrefix/services/';
  /// Categorías de servicios — contiene el campo `is_mobile`.
  static const String servicesCategories = '$apiPrefix/services/categories';

  /// Catálogo de modelos (mismos que la app admin). Todos exponen `image`.
  static const String catalogLashDesigns = '$apiPrefix/catalogs/lash-designs';
  static const String catalogEyeTypes = '$apiPrefix/catalogs/eye-types';
  static const String catalogEffects = '$apiPrefix/catalogs/effects';
  static const String catalogVolumes = '$apiPrefix/catalogs/volumes';

  /// Sucursal por defecto para filtros de agenda.
  static const int defaultBranchId = 1;

  /// URL absoluta para imágenes servidas por el backend (mount `/media`).
  /// Acepta rutas `/media/...`, relativas, o URLs ya absolutas (http/https).
  static String? mediaUrl(String? path) {
    if (path == null) return null;
    final p = path.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final rel = p.startsWith('/') ? p : '/$p';
    return '$host$rel';
  }

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
