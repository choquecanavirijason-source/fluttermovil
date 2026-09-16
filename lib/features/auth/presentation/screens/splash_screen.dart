import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/auth_repository_impl.dart';
import '../../domain/entities/auth_user.dart';
import '../providers/auth_state_provider.dart';

/// Decide la sesión al arrancar: si hay token válido (`/auth/me`) entra al
/// shell; si no, va a login.
///
/// En desarrollo (`Env.kDevSkipLogin`) nunca llega al login: primero intenta
/// el login real como admin y, si el backend no responde, abre una sesión
/// local de admin para entrar igual a la pantalla de inicio.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  /// Login automático de desarrollo (`Env.kDevAutoLogin`): entra directo como
  /// admin sin pasar por la pantalla de login. Usa el login real, así que el
  /// token que queda guardado es válido para el resto de la API.
  /// Devuelve `false` si no aplica o si falló — el llamador sigue con el
  /// flujo normal.
  Future<bool> _devAutoLogin() async {
    if (!Env.kDevAutoLogin) return false;
    try {
      final result = await ref.read(authRepositoryProvider).login(
            Env.kDevAutoLoginUsername,
            Env.kDevAutoLoginPassword,
          );
      await ref
          .read(authStateProvider.notifier)
          .markSignedInWithUser(result.token, result.user);
      developer.log(
        'Auto-login DEV como "${Env.kDevAutoLoginUsername}"',
        name: 'auth.splash',
      );
      return true;
    } catch (e) {
      developer.log('Auto-login DEV falló: $e', name: 'auth.splash', error: e);
      return _offlineAdminSession(e);
    }
  }

  /// Último recurso del modo DEV (`Env.kDevOfflineSessionFallback`): marca la
  /// sesión como iniciada con un admin local y token vacío, para que el
  /// router mande al shell en vez de a la pantalla de login. Las pantallas
  /// que consultan la API mostrarán su error/vacío habitual.
  /// Devuelve `false` si el fallback está apagado.
  Future<bool> _offlineAdminSession(Object cause) async {
    if (!Env.kDevOfflineSessionFallback) return false;
    await ref.read(authStateProvider.notifier).markSignedInWithUser(
          '',
          const AuthUser(
            id: 0,
            username: Env.kDevAutoLoginUsername,
            isActive: true,
            roleName: 'admin',
          ),
        );
    developer.log(
      'Sesión OFFLINE de admin (backend no disponible: $cause)',
      name: 'auth.splash',
    );
    return true;
  }

  Future<void> _hydrate() async {
    if (await _devAutoLogin()) return;
    final auth = ref.read(authStateProvider.notifier);
    final hasToken = await ref.read(secureStorageProvider).hasToken();
    if (!hasToken) {
      if (await _offlineAdminSession('sin token guardado')) return;
      await auth.markSignedOut();
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).me();
      final token = await ref.read(secureStorageProvider).readToken();
      await auth.markSignedInWithUser(token ?? '', user);
    } catch (e) {
      developer.log('Hydrate falló: $e', name: 'auth.splash', error: e);
      if (await _offlineAdminSession(e)) return;
      await auth.markSignedOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.brandPrimary,
    );
  }
}
