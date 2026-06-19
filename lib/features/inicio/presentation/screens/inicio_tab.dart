import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../comisiones/presentation/providers/comisiones_provider.dart';

/// Inicio ("Descubre Tu Mejor Mirada"): pantalla central de la app.
/// Sin barra de pestañas: navegación por íconos/botones.
class InicioTab extends ConsumerWidget {
  const InicioTab({super.key});

  static final _money =
      NumberFormat.currency(locale: 'es_BO', symbol: 'Bs ', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final commission = ref.watch(dailyCommissionProvider(todayOnly));

    return Scaffold(
      backgroundColor: cs.surface,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Hero con foto, curva inferior y botón de perfil arriba.
          ClipPath(
            clipper: _HeroClipper(),
            child: SizedBox(
              height: 330,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/chica2.png',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.1),
                    errorBuilder: (context, error, stack) => const ColoredBox(
                      color: AppColors.brandPrimary,
                      child: Center(
                        child: Icon(Icons.face_retouching_natural,
                            color: Colors.white24, size: 80),
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x55000000), Colors.transparent],
                        stops: [0.0, 0.45],
                      ),
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    right: 14,
                    child: _CircleIconButton(
                      icon: Icons.person_outline,
                      onTap: () => context.push(AppRoutes.perfil),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Transform.translate(
            offset: const Offset(0, -28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Text(
                    'Descubre Tu Mejor Mirada',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Realiza pruebas de estilos, conoce nuestros servicios y '
                    'transforma tus pestañas como nunca antes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionPill(
                          icon: Icons.remove_red_eye_outlined,
                          label: 'Probador',
                          background: AppColors.brandPrimary,
                          foreground: Colors.white,
                          onTap: () => context.push(AppRoutes.selection),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionPill(
                          icon: Icons.auto_awesome_mosaic_outlined,
                          label: 'Servicio',
                          background: AppColors.brandSidebar,
                          foreground: Colors.white,
                          onTap: () => context.push(AppRoutes.servicio),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionPill(
                          icon: Icons.person_outline,
                          label: 'Cliente',
                          background: AppColors.goldAccent,
                          foreground: Colors.black87,
                          onTap: () => context.push(AppRoutes.cliente),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionPill(
                          icon: Icons.savings_outlined,
                          label: 'Comisión',
                          background: AppColors.brandAccent,
                          foreground: Colors.white,
                          onTap: () => context.push(AppRoutes.comision),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  _CommissionStrip(
                    commission: commission,
                    money: _money,
                    onTap: () => context.push(AppRoutes.comision),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 40);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 40,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: foreground, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommissionStrip extends StatelessWidget {
  const _CommissionStrip({
    required this.commission,
    required this.money,
    required this.onTap,
  });

  final AsyncValue<dynamic> commission;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.brandPrimary, AppColors.brandSidebar],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined,
                  color: AppColors.goldAccent, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Comisión de hoy',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13)),
                    const SizedBox(height: 2),
                    commission.when(
                      loading: () => const Text('…',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900)),
                      error: (e, _) => const Text('—',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900)),
                      data: (d) => Text(money.format(d.commission),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
