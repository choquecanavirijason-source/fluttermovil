/// Constantes de endpoints (relativas a `Env.apiBaseUrl`, que ya incluye `/api`).
class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const String login = '/auth/login';
  static const String me = '/auth/me';
  static const String logout = '/auth/logout';

  // Clients
  static const String clients = '/clients/';
  static String clientById(int id) => '/clients/$id';

  // Catálogos
  static const String catalogEyeTypes = '/catalogs/eye-types';
  static const String catalogEffects = '/catalogs/effects';
  static const String catalogVolumes = '/catalogs/volumes';
  static const String catalogLashDesigns = '/catalogs/lash-designs';

  // Servicios
  static const String servicesList = '/services/';
  static const String serviceCategories = '/services/categories';

  // Citas / tickets
  static const String agendaAppointments = '/agenda/appointments';
  static const String agendaMobileAvailable =
      '/agenda/appointments/mobile/available';

  // Reportes
  static const String reportsDailyClosing = '/reports/daily-closing';

  // Tracking (ficha del cliente)
  static const String tracking = '/tracking/';
}
