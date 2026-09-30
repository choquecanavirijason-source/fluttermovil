import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/agenda_service.dart';
import '../../../../core/services/agenda_ws_service.dart';
import '../../../../core/services/local_notifications_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../auth/presentation/providers/auth_state_provider.dart';
import '../../../../core/models/mobile_appointment.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/presentation/providers/clientes_provider.dart';
import '../../../clientes/presentation/providers/new_appointment_watcher.dart';

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
  StreamSubscription<AgendaWsEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(LocalNotificationsService.instance.initialize());
    ref.read(newAppointmentWatcherProvider).start();

    // Conecta al WS de agenda (/ws/branch/{branchId}) para refrescar
    // "Clientes de hoy" y disparar la verificación de citas nuevas al
    // instante, en vez de esperar el sondeo de 3 min.
    final ws = ref.read(agendaWsServiceProvider);
    _wsSub = ws.events.listen(_onAgendaWsEvent);
    unawaited(ws.connect());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(newAppointmentWatcherProvider).stop();
    _wsSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      ref.read(agendaWsServiceProvider).reconnectNow();
    }
  }

  /// Un evento de agenda en vivo (cita creada/llamada/actualizada/eliminada)
  /// refresca "Clientes de hoy" al instante y adelanta la verificación de
  /// clientes nuevos, sin esperar el sondeo periódico.
  void _onAgendaWsEvent(AgendaWsEvent event) {
    final user = ref.read(authUserProvider);
    final belongsToMe =
        event.professionalId == null || event.professionalId == user?.id;
    if (!belongsToMe) return;

    if (event.event == 'ticket_called') {
      _notifyTicketCalled(event);
    }

    ref.invalidate(_todayTicketsProvider);
    ref.read(newAppointmentWatcherProvider).checkNow();
  }

  /// Avisa a la operaria que le llamaron una ficha (es su turno) — el
  /// evento más urgente y accionable del WS, a diferencia de
  /// creaciones/actualizaciones que solo refrescan la lista en silencio.
  void _notifyTicketCalled(AgendaWsEvent event) {
    final tickets = ref.read(_todayTicketsProvider).valueOrNull;
    String? name;
    if (tickets != null) {
      for (final t in tickets) {
        if (t.id == event.ticketId) {
          name = t.clientDisplayName;
          break;
        }
      }
    }
    ref.read(localNotificationsServiceProvider).show(
          id: event.ticketId ?? 0,
          title: 'Te llamaron',
          body: name == null ? 'Es tu turno para atender.' : 'Es tu turno con $name.',
        );
  }

  Future<void> _refresh() async {
    ref.invalidate(_todayTicketsProvider);
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            child: const Text('Cerrar Sesión'),
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
    final user = ref.watch(authUserProvider);
    final ticketsAsync = ref.watch(_todayTicketsProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.brandPrimary,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Hero con info de operaria ─────────────────────────────
            _HeroSection(
              user: user,
              ticketsAsync: ticketsAsync,
              themeMode: themeMode,
              onToggleTheme: () =>
                  ref.read(themeModeProvider.notifier).toggleTheme(),
              onLogout: _logout,
            ),

            // ── Cuerpo principal ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  _StatsRow(
                    ticketsAsync: ticketsAsync,
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
                          onTap: () {
                            ref.read(sessionClientProvider.notifier).state =
                                null;
                            context.push(AppRoutes.selection);
                          },
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
                      Expanded(flex: 1, child: const SizedBox()),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _ActionPill(
                          icon: Icons.person_outline,
                          label: 'Cliente',
                          background: AppColors.goldAccent,
                          foreground: Colors.black87,
                          onTap: () => context.push(AppRoutes.cliente),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(flex: 1, child: const SizedBox()),
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
    required this.themeMode,
    required this.onToggleTheme,
    required this.onLogout,
  });

  final dynamic user;
  final AsyncValue<List<MobileAppointment>> ticketsAsync;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
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
        height: 420,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Foto
            Image.asset(
              'assets/chica2.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0, 0.3),
              errorBuilder: (_, e, _) => const ColoredBox(
                color: AppColors.brandPrimary,
                child: Center(
                  child: Icon(Icons.face_retouching_natural,
                      color: Colors.white24, size: 80),
                ),
              ),
            ),
            // Gradiente superior
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0x88000000), Colors.transparent],
                ),
              ),
            ),
            // Gradiente inferior
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
            ),
            // Controles de tema y sesión
            Positioned(
              top: topPad + 8,
              right: 14,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ThemeModeButton(
                    isDark: themeMode == ThemeMode.dark,
                    onTap: onToggleTheme,
                  ),
                  const SizedBox(width: 8),
                  _StyledLogoutButton(onTap: onLogout),
                ],
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
    required this.skillLevel,
  });

  final AsyncValue<List<MobileAppointment>> ticketsAsync;
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
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

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
                fontSize: 20,
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
// Styled logout button
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: isDark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        shape: const CircleBorder(),
        minimumSize: const Size(48, 48),
        maximumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        isDark ? Icons.light_mode : Icons.dark_mode_outlined,
        size: 24,
      ),
    );
  }
}

enum _AccountMenuAction { profile, logout }

class _StyledLogoutButton extends StatelessWidget {
  const _StyledLogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AccountMenuAction>(
      tooltip: 'Opciones de cuenta',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (action) {
        if (action == _AccountMenuAction.profile) {
          unawaited(context.push(AppRoutes.perfil));
          return;
        }
        onTap();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _AccountMenuAction.profile,
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 18),
              SizedBox(width: 8),
              Text('Ver perfil'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _AccountMenuAction.logout,
          child: Row(
            children: [
              const Icon(Icons.logout, size: 18, color: Color(0xFFB3261E)),
              const SizedBox(width: 8),
              Text(
                'Cerrar sesión',
                style: TextStyle(color: Color(0xFFB3261E)),
              ),
            ],
          ),
        ),
      ],
      // Mismo borde, tamaño y fondo que _ThemeModeButton.
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: const Icon(
          Icons.logout_rounded,
          color: Colors.white,
          size: 31,
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
// Client list section  ← CAMBIOS AQUÍ
// ─────────────────────────────────────────────────────────────────────────────

class _ClientListSection extends ConsumerStatefulWidget {
  const _ClientListSection({required this.ticketsAsync});

  final AsyncValue<List<MobileAppointment>> ticketsAsync;

  @override
  ConsumerState<_ClientListSection> createState() => _ClientListSectionState();
}

class _ClientListSectionState extends ConsumerState<_ClientListSection> {
  static const _activeStatuses = {
    'pending',
    'waiting',
    'confirmed',
    'in_service',
  };

  @override
  void didUpdateWidget(covariant _ClientListSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLatest = _extractLatestClient(oldWidget.ticketsAsync);
    final newLatest = _extractLatestClient(widget.ticketsAsync);
    if ((newLatest != null && oldLatest == null) ||
        (newLatest != null && oldLatest != null && newLatest.id != oldLatest.id))
     {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nuevo cliente: ${newLatest.clientDisplayName}'),
          backgroundColor: AppColors.brandPrimary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ));
      });
    } else if (newLatest != null &&
        oldLatest != null &&
        newLatest.id != oldLatest.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
         content: Text('Nuevo cliente: ${newLatest.clientDisplayName}'),
          backgroundColor: AppColors.brandPrimary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ));
      });
    }
  }

  // ── devuelve el ÚLTIMO cliente asignado (active.last) ──
  MobileAppointment? _extractLatestClient(
      AsyncValue<List<MobileAppointment>> async) {
    final tickets = async.valueOrNull;
    if (tickets == null) return null;
    final active = tickets.where((t) => _activeStatuses.contains(t.status)).toList();
    if (active.isEmpty) return null;
    return active.last; // ← último asignado
  }

  void _openProbador(MobileAppointment ticket) {
    if (ticket.clientId != null) {
      ref.read(sessionClientProvider.notifier).state = Client(
        id: ticket.clientId!,
        displayName: ticket.clientDisplayName,
      );
    }
    context.push(AppRoutes.selection);
  }

  // ── bottom sheet con la lista completa ──────────────────────
  void _showAllClientsSheet(List<MobileAppointment> tickets) {
    final active =
        tickets.where((t) => _activeStatuses.contains(t.status)).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                // Handle
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                // Título
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      const Text(
                        'Todos los clientes de hoy',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${active.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                // Lista
                Expanded(
                  child: active.isEmpty
                      ? const Center(
                          child: Text(
                            'Sin clientes asignados para hoy',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                          itemCount: active.length,
                          itemBuilder: (_, i) => InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _openProbador(active[i]);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: _ClientRow(ticket: active[i]),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Cabecera con label + botón Ver + badge ─────────────────
        widget.ticketsAsync.when(
          loading: () => const _SectionLabel(label: 'Clientes de hoy'),
          error: (_, __) => const _SectionLabel(label: 'Clientes de hoy'),
          data: (tickets) {
            final active = tickets
                .where((t) => _activeStatuses.contains(t.status))
                .toList();
            final count = active.length;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _SectionLabel(label: 'Clientes de hoy'),
                const Spacer(),
                // Botón "Ver" — solo visible si hay más de un cliente
                if (count > 1) ...[
                  GestureDetector(
                    onTap: () => _showAllClientsSheet(tickets),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.55),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.list_alt_outlined,
                              size: 13, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Ver todos',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Badge de conteo
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // ── solo el último cliente asignado ───────────────
        widget.ticketsAsync.when(
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
          error: (_, __) => _EmptyClients(
            icon: Icons.error_outline,
            message: 'No se pudo cargar los clientes',
            color: const Color(0xFFE53935),
          ),
          data: (tickets) {
            final latest = _extractLatestClient(widget.ticketsAsync);
            if (latest == null) {
              return _EmptyClients(
                icon: Icons.event_available_outlined,
                message: 'Sin clientes asignados para hoy',
                color: cs.onSurfaceVariant,
              );
            }
            // Mostramos solo el ÚLTIMO cliente asignado
            return InkWell(
              onTap: () => _openProbador(latest),
              borderRadius: BorderRadius.circular(14),
              child: _ClientRow(ticket: latest),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty clients placeholder
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Client row
// ─────────────────────────────────────────────────────────────────────────────

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.ticket});

  final MobileAppointment ticket;

  String get _clientName => ticket.clientDisplayName
      .replaceFirst(
        RegExp(r'\s+[—–-]\s+Sucursal\b.*$', caseSensitive: false),
        '',
      )
      .trim();

  String get _ticketLabel {
    final code = ticket.ticketCode.trim();
    return code.isEmpty ? '#${ticket.id.toString().padLeft(4, '0')}' : code;
  }

  String? get _appointmentDateTime {
    final startTime = ticket.startTime;
    if (startTime == null) return null;
    final dateTime = DateTime.tryParse(startTime);
    if (dateTime == null) return null;
    return DateFormat('dd/MM/yyyy - HH:mm').format(dateTime.toLocal());
  }

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _statusColor[ticket.status] ?? const Color(0xFF757575);
    final statusTextColor = isDark ? Colors.white70 : statusColor;
    final statusBackground = isDark
      ? const Color(0xFF353535)
      : statusColor.withValues(alpha: 0.12);
    final statusLabel = _statusLabel[ticket.status] ?? ticket.status;
    final appointmentDateTime = _appointmentDateTime;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.primary.withValues(alpha: 0.14),
            child: Text(
              _clientName.isNotEmpty
                  ? _clientName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: theme.textTheme.bodyLarge?.color ?? cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ticket.servicesSummary,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.textTheme.bodyMedium?.color ??
                        cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: cs.outlineVariant,
          ),
          SizedBox(
            width: 126,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: _StatusBadge(
                    label: statusLabel,
                    color: statusTextColor,
                    backgroundColor: statusBackground,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _ticketLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (appointmentDateTime != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            appointmentDateTime,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 3),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.backgroundColor,
  });

  final String label;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
