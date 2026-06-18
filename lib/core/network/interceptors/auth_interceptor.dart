import 'dart:async';

import 'package:dio/dio.dart';

import '../../storage/secure_storage.dart';

typedef SessionExpiredCallback = FutureOr<void> Function();

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.onSessionExpired,
  });

  final SecureStorage storage;
  final SessionExpiredCallback onSessionExpired;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] == true) {
      handler.next(options);
      return;
    }
    final token = await storage.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isSkipAuth = err.requestOptions.extra['skipAuth'] == true;
    if (err.response?.statusCode == 401 && !isSkipAuth) {
      await storage.clearToken();
      await Future.sync(onSessionExpired);
    }
    handler.next(err);
  }
}
