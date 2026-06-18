import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../../core/services/auth_bridge.dart';
import '../../domain/entities/auth_user.dart';

// NOTA: este archivo NO importa de data/ (repo/api) porque dio_client.dart ya
// importa auth_state_provider.dart — importarlo cerraría un ciclo. La
// orquestación de login/hydrate vive en LoginScreen y SplashScreen.

enum AuthStatus { initial, authenticated, unauthenticated }

class AuthStateController extends Notifier<AuthStatus> implements Listenable {
  final ValueNotifier<int> _ticker = ValueNotifier<int>(0);

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;

  @override
  AuthStatus build() {
    ref.onDispose(_ticker.dispose);
    return AuthStatus.initial;
  }

  /// Persiste token + user y marca sesión autenticada.
  Future<void> markSignedInWithUser(String token, AuthUser user) async {
    await ref.read(secureStorageProvider).writeToken(token);
    _currentUser = user;
    // Puente: mantiene viva la capa antigua (ApiClient/AuthSession) usada por
    // las pantallas aún no migradas (probador, recomendación, etc.).
    AuthBridge.sync(token: token, id: user.id, username: user.username, email: user.email);
    _set(AuthStatus.authenticated);
  }

  Future<void> markSignedOut() async {
    await ref.read(secureStorageProvider).clearToken();
    _currentUser = null;
    AuthBridge.clear();
    _set(AuthStatus.unauthenticated);
  }

  void _set(AuthStatus next) {
    if (state == next) return;
    state = next;
    _ticker.value++;
  }

  @override
  void addListener(VoidCallback listener) => _ticker.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _ticker.removeListener(listener);
}

final authStateProvider =
    NotifierProvider<AuthStateController, AuthStatus>(AuthStateController.new);

final authUserProvider = Provider<AuthUser?>((ref) {
  ref.watch(authStateProvider);
  return ref.read(authStateProvider.notifier).currentUser;
});
