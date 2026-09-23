/// Configuración de entorno de la app de operaria.
///
/// El backend se sirve bajo el prefijo `/api`; las imágenes estáticas
/// (`/media/...`) cuelgan de la raíz del host.
class Env {
  Env._();

  // ── Switch rápido local <-> producción ─────────────────────────────────
  // true  = habla con el backend nuevo (Node) corriendo en tu PC/LAN.
  // false = habla con el servidor de producción ([_remoteHost]).
  //
  // Para probar en local con el teléfono físico:
  //  1. PC y teléfono deben estar en la MISMA red WiFi.
  //  2. El backend debe escuchar en todas las interfaces — el `.env` del
  //     servidor ya trae `HOST=0.0.0.0` y `PORT=3001`, así que sirve.
  //  3. Permite el puerto 3001 en el Firewall de Windows si te lo pide
  //     (`netsh advfirewall firewall add rule name="API 3001" dir=in
  //      action=allow protocol=TCP localport=3001`).
  //  4. Verifica que [_defaultLocalHost] siga siendo la IPv4 de tu PC
  //     (`ipconfig` -> adaptador Wi-Fi). Puede cambiar si el router
  //     reasigna la IP; si cambia no hace falta editar este archivo, se
  //     puede sobreescribir al vuelo (ver "Overrides" abajo).
  //  5. Guarda y haz stop + `flutter run` de nuevo (no hot-restart: esta
  //     pantalla usa cámara nativa y el PlatformView crashea).
  // Antes de compilar el APK para el salón, vuelve a ponerlo en false.
  static const bool kUseLocalBackend = false;

  // ── Overrides sin tocar código ─────────────────────────────────────────
  // Todos estos valores se pueden cambiar al lanzar la app, útil cuando el
  // router te da otra IP o pruebas desde el emulador:
  //
  //   flutter run --dart-define=API_HOST=192.168.0.50
  //   flutter run --dart-define=API_HOST=10.0.2.2      (emulador Android)
  //   flutter run --dart-define=API_PREFIX=            (backend sin /api)
  //
  // Ojo: `localhost`/`127.0.0.1` NO sirven desde el teléfono ni desde el
  // emulador — apuntan al propio dispositivo. Desde el emulador Android el
  // localhost de tu PC es `10.0.2.2`; desde el teléfono físico, la IP LAN.

  /// IPv4 del PC en la WiFi (adaptador Wi-Fi, no el 192.168.56.x de
  /// VirtualBox/Docker que no ve el teléfono).
  static const String _defaultLocalHost = '192.168.0.39';

  /// `PORT` del `.env` del backend.
  static const int _defaultLocalPort = 3001;

  static const String _localHost =
      String.fromEnvironment('API_HOST', defaultValue: _defaultLocalHost);
  static const int _localPort =
      int.fromEnvironment('API_PORT', defaultValue: _defaultLocalPort);

  /// Host de producción (sin `/api`, sin barra final).
  static const String _remoteHost = String.fromEnvironment(
    'API_REMOTE_HOST',
    defaultValue: 'http://37.60.247.213',
  );

  /// Host raíz del backend (sin `/api`). Usado para imágenes `/media/...`
  /// y para derivar la URL del WebSocket (`ws://<host>/ws/branch/{id}`).
  static const String host =
      kUseLocalBackend ? 'http://$_localHost:$_localPort' : _remoteHost;

  /// Prefijo bajo el que el backend expone la API REST. El servidor nuevo
  /// mantiene las mismas rutas que el anterior (`/api/auth/login`,
  /// `/api/catalogs/...`), por eso vale igual en local y en producción.
  /// Si tu instancia responde en la raíz (`/auth/login`), lánzala con
  /// `--dart-define=API_PREFIX=` en vez de editar esto.
  static const String apiPrefix =
      String.fromEnvironment('API_PREFIX', defaultValue: '/api');

  /// Base de la API REST — lo que consume `dioProvider`. `ApiEndpoints`
  /// agrega rutas relativas sin repetir el prefijo.
  static const String apiBaseUrl = '$host$apiPrefix';

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
