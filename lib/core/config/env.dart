/// Configuración de entorno de la app de operaria.
///
/// La operaria consume el backend en la **nube** (GCP). El backend se sirve
/// bajo el prefijo `/api`; las imágenes estáticas (`/media/...`) cuelgan de la
/// raíz del host.
class Env {
  Env._();

  /// Host raíz del backend (sin `/api`). Usado para imágenes `/media/...`.
  static const String host = 'http://34.55.150.142';

  /// Base de la API REST (incluye `/api`). `ApiEndpoints` agrega rutas sin `/api`.
  static const String apiBaseUrl = '$host/api';

  /// Puerto directo del backend (uvicorn), usado solo por el WebSocket de
  /// agenda para saltarse nginx (que aún no reenvía `/ws/` en producción).
  /// El REST sigue yendo por nginx (`apiBaseUrl`, puerto 80/443) sin cambios.
  static const int wsDirectPort = 8000;

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  static const bool isDevelopment = true;

  static const String tokenStorageKey = '_tkn';
  static const String selectedBranchPrefsKey = 'selected_branch_id';
  /// Prefijo de clave; [NewAppointmentWatcher] le agrega `_<userId>` para no
  /// mezclar el estado entre operarias que comparten el dispositivo.
  static const String knownAppointmentIdsPrefsKey = 'known_appointment_ids';
  static const String locale = 'es_BO';
  static const String currencyCode = 'BOB';
  static const String currencySymbol = 'Bs';

  static const int defaultBranchId = 1;

  /// URL absoluta para imágenes servidas por el backend (`/media/...`).
  /// Acepta rutas relativas o URLs ya absolutas.
  static String? mediaUrl(String? path) {
    if (path == null) return null;
    final p = path.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    return '$host${p.startsWith('/') ? p : '/$p'}';
  }
}
