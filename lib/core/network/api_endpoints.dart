/// Constantes de endpoints (relativas a `Env.apiBaseUrl`, que ya incluye `/api`).
class ApiEndpoints {
  ApiEndpoints._();

  // Base URL GCP (referencia explícita; el valor canónico vive en Env.apiBaseUrl)
  static const String gcpBaseUrl = 'http://34.55.150.142/api';

  // Catálogos — raíz general
  static const String catalogs = '/catalogs/';

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
  /// "Diseños" del admin (combos con imagen + modelo 3D) — distinto de
  /// [catalogLashDesigns] ("Tecnología" en el sidebar del admin, solo
  /// nombres). Este es el catálogo real que usa el Probador.
  static const String catalogDesigns = '/catalogs/designs';

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
