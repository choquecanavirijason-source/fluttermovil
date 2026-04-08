import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:test_face/screens/probador.dart';

import '../screens/Login.dart';
import '../screens/Home.dart';
import '../eye_tracking_page.dart';
//import '../screens/Probador.dart';
import '../screens/servicio.dart';
import '../screens/cliente.dart';
import '../screens/work_assistant_screen.dart';
import '../work_assistant_args.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
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
 //   GoRoute(
 //     path: '/probador',
 //     name: 'probador',
 //     builder: (BuildContext context, GoRouterState state) =>
  //        const ProbadorScreen(),
 //   ),
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
