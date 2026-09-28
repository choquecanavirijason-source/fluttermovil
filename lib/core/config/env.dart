/// Configuración de entorno de la app de operaria.
class Env {
  Env._();

  static const bool kUseLocalBackend = false;
  static const String _localLanIp = '37.60.247.213';

  /// Host raíz del backend (sin `/api`).
  static const String host =
      kUseLocalBackend ? 'http://$_localLanIp:8000' : 'http://37.60.247.213';

  /// Base de la API REST.
  static const String apiBaseUrl = kUseLocalBackend ? host : '$host/api';

  /// Compatibility field used by ApiConfig on develop.
  static const String apiPrefix = kUseLocalBackend ? '' : '/api';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  static const bool isDevelopment = true;

  // ── Auto-login de desarrollo (SALTA EL LOGIN) ──────────────────────────
  // true  = al arrancar, SplashScreen hace login real contra /auth/login con
  //         las credenciales de abajo y entra directo al shell como admin.
  //         El token es real, así que todas las llamadas a la API funcionan.
  // false = flujo normal (token guardado -> /auth/me, o pantalla de login).
  //
  // Si el login automático falla (credenciales malas, backend caído) la app
  // NO se traba: cae al flujo normal y muestra la pantalla de login.
  //
  // Ponlo en false antes de compilar el APK para el salón: deja el usuario y
  // la contraseña en texto plano dentro del binario.
  static const bool kDevAutoLogin = false;
  static const String kDevAutoLoginUsername =
      String.fromEnvironment('DEV_USER', defaultValue: 'admin');
  static const String kDevAutoLoginPassword =
      String.fromEnvironment('DEV_PASS', defaultValue: 'admin');

  // Si el auto-login falla (backend caído, sin red, credenciales cambiadas)
  // y esto está en true, la app NO muestra la pantalla de login: abre una
  // sesión local de admin (sin token) y entra igual al shell. Las pantallas
  // que piden datos a la API mostrarán su propio error/vacío, pero nunca
  // rebota al login. Solo para desarrollo — ponlo en false junto con
  // [kDevAutoLogin] antes de compilar el APK del salón.
  static const bool kDevOfflineSessionFallback = false;

  /// True cuando la app debe comportarse como "siempre logueada": nunca
  /// navega al login, ni al arrancar ni tras un 401.
  static const bool kDevSkipLogin = kDevAutoLogin && kDevOfflineSessionFallback;

  static const String tokenStorageKey = '_tkn';
  static const String selectedBranchPrefsKey = 'selected_branch_id';
  /// Prefijo de clave; [NewAppointmentWatcher] le agrega `_<userId>` para no
  /// mezclar el estado entre operarias que comparten el dispositivo.
  static const String knownAppointmentIdsPrefsKey = 'known_appointment_ids';
  static const String locale = 'es_BO';
  static const String currencyCode = 'BOB';
  static const String currencySymbol = 'Bs';

  static const int defaultBranchId = 1;

  /// URL/URI para imágenes servidas por el backend (`/media/...`).
  /// Acepta rutas relativas, URLs ya absolutas, o imágenes embebidas como
  /// `data:` URI (ej. el campo `image` de "Diseños" del admin puede venir
  /// en base64 en vez de una ruta de archivo) — estas viajan tal cual, sin
  /// prefijo de host, o `Image.network` fallaría con una URL inválida.
  ///
  /// Si el backend nuevo devuelve URLs firmadas de almacenamiento
  /// (`STORAGE_ENDPOINT`), llegan absolutas y pasan sin tocar.
  static String? mediaUrl(String? path) {
    if (path == null) return null;
    final p = path.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('data:')) {
      return p;
    }
    return '$host${p.startsWith('/') ? p : '/$p'}';
  }
}
