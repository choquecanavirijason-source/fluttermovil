import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

const _kTokenKey = 'operaria_auth_token';

class LoginUser {
  final int id;
  final String username;
  final String? email;

  const LoginUser({
    required this.id,
    required this.username,
    required this.email,
  });

  factory LoginUser.fromMap(Map<String, dynamic> map) {
    return LoginUser(
      id: (map['id'] as num?)?.toInt() ?? 0,
      username: (map['username'] as String?) ?? '',
      email: map['email'] as String?,
    );
  }
}

class LoginResponse {
  final String accessToken;
  final String tokenType;
  final LoginUser user;
  final String? expiresAt;
  final int? expiresInMinutes;

  const LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.user,
    required this.expiresAt,
    required this.expiresInMinutes,
  });

  factory LoginResponse.fromMap(Map<String, dynamic> map) {
    return LoginResponse(
      accessToken: (map['access_token'] as String?) ?? '',
      tokenType: (map['token_type'] as String?) ?? 'bearer',
      user: LoginUser.fromMap(
        (map['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      expiresAt: map['expires_at'] as String?,
      expiresInMinutes: (map['expires_in_minutes'] as num?)?.toInt(),
    );
  }
}

class AuthSession {
  static String? accessToken;
  static LoginUser? currentUser;

  static bool get isLoggedIn =>
      accessToken != null && accessToken!.isNotEmpty;
}

class AuthService {
  /// Restaura el token guardado al iniciar la app.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kTokenKey);
    if (token != null && token.isNotEmpty) {
      AuthSession.accessToken = token;
    }
  }

  /// Cierra sesión: borra token de memoria y de almacenamiento.
  static Future<void> logout() async {
    AuthSession.accessToken = null;
    AuthSession.currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }

  Future<LoginResponse> login({
    required String username,
    required String password,
  }) async {
    final httpClient = HttpClient();
    try {
      final uri = ApiConfig.uri(ApiConfig.authLogin);
      final request = await httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, dynamic>{
          'username': username,
          'password': password,
        }),
      );

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'Error de autenticacion (${response.statusCode})';
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            final detail = decoded['detail']?.toString();
            if (detail != null && detail.isNotEmpty) {
              message = detail;
            }
          }
        } catch (_) {}
        throw Exception(message);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Respuesta de login invalida');
      }

      final data = LoginResponse.fromMap(decoded);
      if (data.accessToken.isEmpty) {
        throw Exception('No se recibio access_token');
      }

      // Guarda en memoria y en disco
      AuthSession.accessToken = data.accessToken;
      AuthSession.currentUser = data.user;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, data.accessToken);

      return data;
    } on SocketException {
      throw Exception('No se pudo conectar con la API');
    } finally {
      httpClient.close(force: true);
    }
  }

  /// `GET /api/auth/me` — requiere [AuthSession.accessToken].
  Future<LoginUser> fetchCurrentUser() async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('No hay sesion activa');
    }

    final httpClient = HttpClient();
    try {
      final uri = ApiConfig.uri(ApiConfig.authMe);
      final request = await httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Error al cargar perfil (${response.statusCode})');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Respuesta de perfil invalida');
      }

      final user = LoginUser.fromMap(decoded);
      AuthSession.currentUser = user;
      return user;
    } on SocketException {
      throw Exception('No se pudo conectar con la API');
    } finally {
      httpClient.close(force: true);
    }
  }
}
