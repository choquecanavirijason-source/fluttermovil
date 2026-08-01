/// Configuración de entorno de la app de operaria.
///
/// La operaria consume el backend en la **nube** (GCP). El backend se sirve
/// bajo el prefijo `/api`; las imágenes estáticas (`/media/...`) cuelgan de la
/// raíz del host.
class Env {
  Env._();

  // ── Switch rápido local <-> producción ─────────────────────────────────
  // true  = habla con tu elashesbackend corriendo en tu PC (Docker, LAN).
  // false = habla con el servidor de producción en GCP.
  //
  // Para probar en local con el teléfono físico:
  //  1. PC y teléfono deben estar en la MISMA red WiFi.
  //  2. El backend debe estar corriendo y escuchando en todas las interfaces
  //     (el contenedor Docker `elashes-backend` ya expone 0.0.0.0:8000).
  //  3. Permite el puerto 8000 en el Firewall de Windows si te lo pide.
  //  4. Actualiza _localLanIp con la IP de tu PC (ipconfig -> "Dirección
  //     IPv4" del adaptador WiFi). Puede cambiar si tu router reasigna la IP.
  //  5. Pon kUseLocalBackend en true, guarda y haz stop + `flutter run` de
  //     nuevo (no hot-restart: esta pantalla usa cámara nativa, ver nota en
  //     el chat sobre crashes de hot-restart con PlatformView).
  // Antes de compilar el APK para el salón, vuelve a ponerlo en false.
  static const bool kUseLocalBackend = false;
  static const String _localLanIp = '192.168.1.6';

  /// Host raíz del backend (sin `/api`). Usado para imágenes `/media/...`.
  static const String host =
      kUseLocalBackend ? 'http://$_localLanIp:8000' : 'http://34.55.150.142';

  /// Base de la API REST. En producción el backend cuelga detrás de un
  /// proxy que expone las rutas bajo `/api` (por eso `$host/api`); el
  /// contenedor Docker local NO tiene ese proxy — FastAPI ahí responde
  /// directo en la raíz (`/auth/login`, no `/api/auth/login`), confirmado
  /// con `GET /openapi.json` contra localhost:8000. `ApiEndpoints` agrega
  /// rutas sin `/api` en ambos casos.
  static const String apiBaseUrl = kUseLocalBackend ? host : '$host/api';

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

  /// URL/URI para imágenes servidas por el backend (`/media/...`).
  /// Acepta rutas relativas, URLs ya absolutas, o imágenes embebidas como
  /// `data:` URI (ej. el campo `image` de "Diseños" del admin puede venir
  /// en base64 en vez de una ruta de archivo) — estas viajan tal cual, sin
  /// prefijo de host, o `Image.network` fallaría con una URL inválida.
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
