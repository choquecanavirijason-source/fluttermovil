import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../error/api_exception.dart';
import 'empty_state.dart';
import 'loader_screen.dart';

/// Renderiza un `AsyncValue<T>`: loading → loader, error → EmptyState + retry,
/// data → builder.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingMessage,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final String? loadingMessage;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => LoaderScreen(message: loadingMessage),
      error: (error, _) {
        final message = error is ApiException
            ? error.message
            : (error is DioException && error.error is ApiException)
                ? (error.error as ApiException).message
                : 'Ocurrió un error inesperado.';
        return EmptyState(
          icon: Icons.error_outline,
          title: 'No pudimos cargar la información',
          message: message,
          action: onRetry == null
              ? null
              : FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
        );
      },
      data: builder,
    );
  }
}
