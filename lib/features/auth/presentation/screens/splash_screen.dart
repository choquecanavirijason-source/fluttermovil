import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/auth_repository_impl.dart';
import '../providers/auth_state_provider.dart';

/// Decide la sesión al arrancar: si hay token válido (`/auth/me`) entra al
/// shell; si no, va a login.
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

  Future<void> _hydrate() async {
    final auth = ref.read(authStateProvider.notifier);
    final hasToken = await ref.read(secureStorageProvider).hasToken();
    if (!hasToken) {
      await auth.markSignedOut();
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).me();
      final token = await ref.read(secureStorageProvider).readToken();
      await auth.markSignedInWithUser(token ?? '', user);
    } catch (e) {
      developer.log('Hydrate falló: $e', name: 'auth.splash', error: e);
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
