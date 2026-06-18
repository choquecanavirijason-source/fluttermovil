import 'auth_service.dart';

/// Puente transitorio: replica el token/usuario del nuevo stack (Dio +
/// SecureStorage) hacia la capa antigua (`AuthSession`/`ApiClient`) que aún
/// usan las pantallas no migradas (probador, recomendación, catálogo, etc.).
///
/// Se elimina cuando todas las pantallas usen Dio.
class AuthBridge {
  AuthBridge._();

  static void sync({
    required String token,
    required int id,
    required String username,
    String? email,
  }) {
    AuthSession.accessToken = token;
    AuthSession.currentUser = LoginUser(id: id, username: username, email: email);
  }

  static void clear() {
    AuthSession.accessToken = null;
    AuthSession.currentUser = null;
  }
}
