import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:test_face/screens/probador.dart';

import '../core/services/auth_service.dart';
import '../screens/Login.dart';
import '../screens/Home.dart';
import '../eye_tracking_page.dart';
import '../screens/servicio.dart';
import '../screens/cliente.dart';
import '../screens/catalogo.dart';
import '../screens/mi_dia.dart';
import '../screens/recomendacion.dart';
import '../screens/work_assistant_screen.dart';
import '../work_assistant_args.dart';
import '../recommendation_args.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (BuildContext context, GoRouterState state) {
    final loggedIn = AuthSession.isLoggedIn;
    final onLogin = state.matchedLocation == '/';
    if (!loggedIn && !onLogin) return '/';
    if (loggedIn && onLogin) return '/home';
    return null;
  },
  routes: <GoRoute>[
    GoRoute(
      path: '/',
      name: 'login',
      builder: (BuildContext context, GoRouterState state) => const LoginPage(),
    ),
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (BuildContext context, GoRouterState state) => const HomePage(),
    ),
    GoRoute(
      path: '/camera',
      name: 'camera',
      builder: (BuildContext context, GoRouterState state) => EyeTrackingPage(),
    ),
    GoRoute(
      path: '/selection',
      name: 'selection',
      builder: (BuildContext context, GoRouterState state) =>
          const ProbadorScreen(),
    ),
    GoRoute(
      path: '/servicio',
      name: 'servicio',
      builder: (BuildContext context, GoRouterState state) {
        final nombre = state.extra as String?;
        return ServicioPage(nombre: nombre ?? 'Cliente');
      },
    ),
    GoRoute(
      path: '/cliente',
      name: 'cliente',
      builder: (BuildContext context, GoRouterState state) =>
          const ClientePage(),
    ),
    GoRoute(
      path: '/catalogo',
      name: 'catalogo',
      builder: (BuildContext context, GoRouterState state) =>
          const CatalogoScreen(),
    ),
    GoRoute(
      path: '/mi-dia',
      name: 'mi-dia',
      builder: (BuildContext context, GoRouterState state) =>
          const MiDiaScreen(),
    ),
    GoRoute(
      path: '/recomendacion',
      name: 'recomendacion',
      builder: (BuildContext context, GoRouterState state) {
        final args = state.extra as RecommendationArgs;
        return RecomendacionScreen(args: args);
      },
    ),
    GoRoute(
      path: '/work-assistant',
      name: 'work-assistant',
      builder: (BuildContext context, GoRouterState state) {
        final extra = state.extra;
        final args = extra is WorkAssistantArgs ? extra : null;
        return WorkAssistantScreen(args: args);
      },
    ),
  ],
);
