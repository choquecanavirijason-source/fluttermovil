import 'entities/auth_user.dart';

class AuthLoginResult {
  const AuthLoginResult({required this.token, required this.user});
  final String token;
  final AuthUser user;
}

abstract class AuthRepository {
  Future<AuthLoginResult> login(String username, String password);
  Future<AuthUser> me();
}
