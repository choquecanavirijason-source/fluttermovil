import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/auth_repository_impl.dart';
import '../providers/auth_state_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscure = true;
  String? _errorMessage;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _errorText(Object e) {
    if (e is ApiException) return e.message;
    if (e is DioException && e.error is ApiException) {
      return (e.error as ApiException).message;
    }
    return 'No se pudo iniciar sesión. Intenta de nuevo.';
  }

  Future<void> _onLogin() async {
    final username = _userController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Completa usuario y contraseña.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result =
          await ref.read(authRepositoryProvider).login(username, password);
      await ref
          .read(authStateProvider.notifier)
          .markSignedInWithUser(result.token, result.user);
    } catch (e, st) {
      developer.log('Login fallido',
          name: 'auth.login', error: e, stackTrace: st);
      if (mounted) setState(() => _errorMessage = _errorText(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(),
            ColoredBox(
              color: cs.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Iniciar sesión',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Comienza tu viaje de belleza',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 15),
                      ),
                      const SizedBox(height: 26),
                      _UnderlineField(
                        label: 'Usuario',
                        hint: 'Ingresa tu usuario',
                        icon: Icons.person_outline,
                        controller: _userController,
                      ),
                      const SizedBox(height: 18),
                      _UnderlineField(
                        label: 'Contraseña',
                        hint: 'Ingresa tu contraseña',
                        icon: Icons.lock_outline,
                        controller: _passwordController,
                        obscure: _obscure,
                        onToggleObscure: () =>
                            setState(() => _obscure = !_obscure),
                        onSubmitted: (_) => _onLogin(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: _errorMessage!),
                      ],
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          onPressed: _isLoading ? null : _onLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4, color: Colors.white),
                                )
                              : const Text('Iniciar Sesión',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: imagen borde a borde con curva solo en la parte inferior
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _BottomCurveClipper(),
      child: SizedBox(
        height: 320,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.brandPrimary),
            Image.asset(
              'assets/chica.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0, 0.3),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// Solo curva convexa en la parte inferior; lados completamente rectos
class _BottomCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const curveHeight = 40.0;
    final path = Path()
      ..lineTo(0, size.height - curveHeight)
      ..quadraticBezierTo(
        size.width / 2,
        size.height + curveHeight,
        size.width,
        size.height - curveHeight,
      )
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Form widgets
// ─────────────────────────────────────────────────────────────────────────────

class _UnderlineField extends StatelessWidget {
  const _UnderlineField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscure = false,
    this.onToggleObscure,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
        TextField(
          controller: controller,
          obscureText: obscure,
          onSubmitted: onSubmitted,
          autocorrect: false,
          enableSuggestions: !obscure,
          style: TextStyle(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            prefixIcon: Icon(icon, color: cs.primary),
            suffixIcon: onToggleObscure != null
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: cs.primary.withValues(alpha: 0.5), width: 1.4),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.offlineRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.offlineRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.offlineRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.offlineRed)),
          ),
        ],
      ),
    );
  }
}
