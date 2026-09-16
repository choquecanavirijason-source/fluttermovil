import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../storage/secure_storage.dart';
import '../../features/auth/presentation/providers/auth_state_provider.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/logging_interceptor.dart';

/// `Dio` configurado para la API de Elashes (operaria → nube).
final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final authState = ref.watch(authStateProvider.notifier);

  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: Env.connectTimeout,
      receiveTimeout: Env.receiveTimeout,
      sendTimeout: Env.sendTimeout,
      contentType: 'application/json',
      responseType: ResponseType.json,
    ),
  )..interceptors.addAll([
      AuthInterceptor(
        storage: storage,
        // Con el bypass de login DEV activo un 401 no debe expulsar al login:
        // la sesión se mantiene y cada pantalla muestra su propio error.
        onSessionExpired: Env.kDevSkipLogin ? () {} : authState.markSignedOut,
      ),
      if (Env.isDevelopment) const LoggingInterceptor(),
      const ErrorInterceptor(),
    ]);

  return dio;
});
