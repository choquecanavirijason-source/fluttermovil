import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_state_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/inicio/presentation/screens/inicio_tab.dart';
import '../../features/comisiones/presentation/screens/mi_comision_screen.dart';
import '../../features/perfil/presentation/screens/perfil_tab.dart';
// Pantallas existentes (capa antigua, accesibles vía puente de token).
import '../../eye_tracking_page.dart';
import '../../screens/probador.dart';
import '../../screens/servicio.dart';
import '../../screens/work_assistant_screen.dart';
import '../../features/catalogo/presentation/screens/catalogo_screen.dart';
import '../../features/clientes/presentation/screens/clientes_screen.dart';
import '../../features/clientes/presentation/screens/cliente_detalle_screen.dart';
import '../../features/clientes/domain/entities/client.dart';
import '../../features/recomendacion/presentation/screens/recomendacion_screen.dart';
import '../../work_assistant_args.dart';
import '../../recommendation_args.dart';
import '../recommendation/eye_shape_analyzer.dart';
import 'guards.dart';
import 'routes.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final authController = ref.watch(authStateProvider.notifier);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: authController,
    redirect: (context, state) =>
        sessionRedirect(state, ref.read(authStateProvider)),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.shell,
        builder: (_, __) => const InicioTab(),
      ),
      GoRoute(
        path: AppRoutes.comision,
        builder: (_, __) => const MiComisionScreen(),
      ),
      GoRoute(
        path: AppRoutes.perfil,
        builder: (_, __) => const PerfilTab(),
      ),
      GoRoute(
        path: AppRoutes.camera,
        builder: (_, __) => const EyeTrackingPage(),
      ),
      GoRoute(
        path: AppRoutes.selection,
        builder: (_, __) => const ProbadorScreen(),
      ),
      GoRoute(
        path: AppRoutes.servicio,
        builder: (_, state) =>
            ServicioPage(nombre: (state.extra as String?) ?? 'Cliente'),
      ),
      GoRoute(
        path: AppRoutes.cliente,
        builder: (_, __) => const ClientesScreen(),
      ),
      GoRoute(
        path: AppRoutes.clienteDetalle,
        builder: (_, state) =>
            ClienteDetalleScreen(client: state.extra as Client),
      ),
      GoRoute(
        path: AppRoutes.catalogo,
        builder: (_, __) => const CatalogoScreen(),
      ),
      GoRoute(
        path: AppRoutes.workAssistant,
        builder: (_, state) {
          final extra = state.extra;
          return WorkAssistantScreen(
            args: extra is WorkAssistantArgs ? extra : null,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.recomendacion,
        builder: (_, state) {
          final extra = state.extra;
          final args = extra is RecommendationArgs
              ? extra
              : const RecommendationArgs(analysis: EyeAnalysis.none);
          return RecomendacionScreen(args: args);
        },
      ),
    ],
  );
});
