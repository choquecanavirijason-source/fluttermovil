import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/agenda_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_state_provider.dart';
import '../../../comisiones/presentation/providers/comisiones_provider.dart';
import '../../../../core/models/mobile_appointment.dart';

final _todayTicketsProvider =
    FutureProvider.autoDispose<List<MobileAppointment>>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user == null) return [];
  return AgendaService.fetchTodayAppointments(
    professionalId: user.id,
    branchId: user.branchId,
  );
});

class InicioTab extends ConsumerStatefulWidget {
  const InicioTab({super.key});

  @override
  ConsumerState<InicioTab> createState() => _InicioTabState();
}

class _InicioTabState extends ConsumerState<InicioTab>
    with WidgetsBindingObserver {
  static final _money =
      NumberFormat.currency(locale: 'es_BO', symbol: 'Bs ', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    ref.invalidate(_todayTicketsProvider);
    ref.invalidate(dailyCommissionProvider(todayOnly));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Segura que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(authStateProvider.notifier).markSignedOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final user = ref.watch(authUserProvider);
    final commission = ref.watch(dailyCommissionProvider(todayOnly));
    final ticketsAsync = ref.watch(_todayTicketsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.brandPrimary,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Hero con info de operaria ─────────────────────────────
            _HeroSection(user: user, ticketsAsync: ticketsAsync, onLogout: _logout),

            // ── Cuerpo principal ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  _StatsRow(
                    ticketsAsync: ticketsAsync,
                    commission: commission,
                    money: _money,
                    skillLevel: user?.skillLevel,
                  ),
                  const SizedBox(height: 24),

                  // Action pills
                  _SectionLabel(label: 'Acciones rápidas'),
                  const SizedBox(height: 12),
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
                      const SizedBox(width: 10),
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
                  const SizedBox(height: 10),
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
                      const SizedBox(width: 10),
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
                  const SizedBox(height: 28),

                  // Client list
                  _ClientListSection(ticketsAsync: ticketsAsync),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero section
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.user,
    required this.ticketsAsync,
    required this.onLogout,
  });

  final dynamic user;
  final AsyncValue<List<MobileAppointment>> ticketsAsync;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final busy = ticketsAsync.valueOrNull?.any((t) => t.status == 'in_service') ?? false;
    final initial = (user?.username as String?)?.isNotEmpty == true
        ? (user!.username as String)[0].toUpperCase()
        : '?';
    final username = (user?.username as String?) ?? '—';
    final branchName = (user?.branchName as String?) ?? '';

    return ClipPath(
      clipper: _HeroClipper(),
      child: SizedBox(
        height: 400 + topPad,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Foto
            Image.asset(
              'assets/chica2.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0, 1.5),
              errorBuilder: (_, e, _) => const ColoredBox(
                color: AppColors.brandPrimary,
                child: Center(
                  child: Icon(Icons.face_retouching_natural,
                      color: Colors.white24, size: 80),
                ),
              ),
            ),
            // Gradiente superior (para botón de perfil)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0x88000000), Colors.transparent],
                ),
              ),
            ),
            // Gradiente inferior (para info operaria)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
            ),
            // Botón cerrar sesión
            Positioned(
              top: topPad + 8,
              right: 14,
              child: _CircleIconButton(
                icon: Icons.logout,
                onTap: onLogout,
              ),
            ),
            // Info operaria (bottom)
            Positioned(
              left: 18,
              right: 18,
              bottom: 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brandPrimary,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Nombre y sucursal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '¡Hola, $username!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (branchName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 13, color: Colors.white70),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  branchName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Status badge
                  _StatusBadgeHero(busy: busy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge (versión hero — sobre fondo oscuro)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadgeHero extends StatelessWidget {
  const _StatusBadgeHero({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = busy ? const Color(0xFFFF5252) : const Color(0xFF69F0AE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            busy ? 'Ocupada' : 'Libre',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.ticketsAsync,
    required this.commission,
    required this.money,
    required this.skillLevel,
  });

  final AsyncValue<List<MobileAppointment>> ticketsAsync;
  final AsyncValue<dynamic> commission;
  final NumberFormat money;
  final int? skillLevel;

  static const _activeStatuses = {'pending', 'waiting', 'confirmed', 'in_service'};

  @override
  Widget build(BuildContext context) {
    final totalToday = ticketsAsync.valueOrNull
            ?.where((t) => _activeStatuses.contains(t.status))
            .length ??
        0;
    final inService = ticketsAsync.valueOrNull
            ?.where((t) => t.status == 'in_service')
            .length ??
        0;
    final commissionValue = commission.valueOrNull;
    final commissionStr = commissionValue != null
        ? money.format(commissionValue.commission)
        : '—';

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.people_alt_outlined,
            iconColor: AppColors.brandPrimary,
            value: ticketsAsync.isLoading ? '…' : '$totalToday',
            label: 'Clientes hoy',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.cut_outlined,
            iconColor: inService > 0 ? const Color(0xFF2E7D32) : AppColors.goldAccent,
            value: ticketsAsync.isLoading ? '…' : '$inService',
            label: 'En servicio',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.savings_outlined,
            iconColor: AppColors.brandAccent,
            value: commission.isLoading ? '…' : commissionStr,
            label: 'Comisión hoy',
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.compact = false,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: compact ? 13 : 20,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Circle icon button (for hero top-right)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Hero clipper
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Action pill
// ─────────────────────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 19),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Client list section
// ─────────────────────────────────────────────────────────────────────────────

class _ClientListSection extends StatelessWidget {
  const _ClientListSection({required this.ticketsAsync});

  final AsyncValue<List<MobileAppointment>> ticketsAsync;

  static const _activeStatuses = {
    'pending',
    'waiting',
    'confirmed',
    'in_service',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel(label: 'Clientes de hoy'),
            const Spacer(),
            ticketsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (tickets) {
                final count = tickets
                    .where((t) => _activeStatuses.contains(t.status))
                    .length;
                if (count == 0) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        ticketsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, e) => _EmptyClients(
            icon: Icons.error_outline,
            message: 'No se pudo cargar los clientes',
            color: const Color(0xFFE53935),
          ),
          data: (tickets) {
            final active = tickets
                .where((t) => _activeStatuses.contains(t.status))
                .toList();
            if (active.isEmpty) {
              return _EmptyClients(
                icon: Icons.event_available_outlined,
                message: 'Sin clientes asignados para hoy',
                color: cs.onSurfaceVariant,
              );
            }
            return Column(
              children: active.map((t) => _ClientRow(ticket: t)).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EmptyClients extends StatelessWidget {
  const _EmptyClients({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.ticket});

  final MobileAppointment ticket;

  static const _statusLabel = {
    'pending': 'Pendiente',
    'waiting': 'En espera',
    'confirmed': 'Confirmado',
    'in_service': 'En servicio',
  };

  static const _statusColor = {
    'pending': Color(0xFF757575),
    'waiting': Color(0xFFE65100),
    'confirmed': Color(0xFF1565C0),
    'in_service': Color(0xFF2E7D32),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor[ticket.status] ?? const Color(0xFF757575);
    final statusLabel = _statusLabel[ticket.status] ?? ticket.status;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.14),
            child: Text(
              ticket.clientDisplayName.isNotEmpty
                  ? ticket.clientDisplayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: AppColors.brandPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.clientDisplayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ticket.servicesSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
