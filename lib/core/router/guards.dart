import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_state_provider.dart';
import 'routes.dart';

/// Redirect global basado en el estado de autenticación.
String? sessionRedirect(GoRouterState state, AuthStatus status) {
  final location = state.matchedLocation;
  final isLogin = location == AppRoutes.login;
  final isSplash = location == AppRoutes.splash;

  if (status == AuthStatus.initial) {
    return isSplash ? null : AppRoutes.splash;
  }
  if (status == AuthStatus.unauthenticated) {
    return isLogin ? null : AppRoutes.login;
  }
  // authenticated
  if (isLogin || isSplash) {
    return AppRoutes.shell;
  }
  return null;
}
