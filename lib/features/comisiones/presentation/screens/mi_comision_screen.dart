import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/presentation/organisms/async_value_view.dart';
import '../../../../core/services/agenda_ws_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_state_provider.dart';
import '../../domain/entities/daily_commission.dart';
import '../providers/comisiones_provider.dart';

class MiComisionScreen extends ConsumerWidget {
  const MiComisionScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  static final _money =
      NumberFormat.currency(locale: 'es_BO', symbol: 'Bs ', decimalDigits: 2);

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Refresca "Mi comisión" en vivo cuando llega un evento de agenda del WS
  /// (`/ws/branch/{branchId}`) que le pertenece a esta operaria y la fecha
  /// que está viendo es hoy — igual que "Clientes de hoy" en el home, pero
  /// no tiene sentido refrescar un día ya cerrado.
  void _listenAgendaWs(WidgetRef ref, DateTime selected) {
    ref.listen<AsyncValue<AgendaWsEvent>>(agendaWsEventsProvider,
        (previous, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      if (!_isSameDay(selected, DateTime.now())) return;

      final user = ref.read(authUserProvider);
      final belongsToMe =
          event.professionalId == null || event.professionalId == user?.id;
      if (!belongsToMe) return;

      ref.invalidate(dailyCommissionProvider(selected));
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedCommissionDateProvider);
    final async = ref.watch(dailyCommissionProvider(selected));
    _listenAgendaWs(ref, selected);

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: const Text('Mi comisión'),
              actions: [
                IconButton(
                  tooltip: 'Elegir fecha',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () => _pickDate(context, ref, selected),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          if (!showAppBar) const SizedBox(height: 8),
          _WeekStrip(
            selected: selected,
            onSelect: (d) =>
                ref.read(selectedCommissionDateProvider.notifier).state = d,
            onPickMonth: () => _pickDate(context, ref, selected),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(dailyCommissionProvider(selected)),
              child: AsyncValueView<DailyCommission>(
                value: async,
                onRetry: () => ref.invalidate(dailyCommissionProvider(selected)),
                builder: (data) => _Body(data: data, money: _money),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    DateTime selected,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(selectedCommissionDateProvider.notifier).state =
          _dateOnly(picked);
    }
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.onSelect,
    required this.onPickMonth,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPickMonth;

  static const _labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    final days = List.generate(7, (i) => _dateOnly(monday.add(Duration(days: i))));
    final today = _dateOnly(DateTime.now());
    final monthLabel = toBeginningOfSentenceCase(
      DateFormat('MMMM yyyy', 'es').format(selected),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                monthLabel,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onPickMonth,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.calendar_month,
                      size: 18, color: AppColors.goldAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: _DayCell(
                    day: days[i],
                    weekday: _labels[i],
                    selected: days[i] == _dateOnly(selected),
                    isToday: days[i] == today,
                    isFuture: days[i].isAfter(today),
                    onTap: () => onSelect(days[i]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.weekday,
    required this.selected,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final DateTime day;
  final String weekday;
  final bool selected;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: isFuture ? null : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.goldAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              weekday,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black87 : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: selected
                    ? Colors.black87
                    : isFuture
                        ? cs.onSurface.withValues(alpha: 0.3)
                        : cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday && !selected
                    ? AppColors.goldAccent
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.money});

  final DailyCommission data;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 28 + MediaQuery.of(context).padding.bottom),
      children: [
        _SummaryCard(data: data, money: money),
        const SizedBox(height: 18),
        Row(
          children: [
            Text('Servicios del día',
                style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const Spacer(),
            Text('${data.items.length}',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        if (data.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.event_busy, size: 44, color: cs.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text('No registraste servicios este día.',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          )
        else
          ...data.items.map((it) => _ItemCard(item: it, money: money)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data, required this.money});

  final DailyCommission data;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandPrimary, AppColors.brandSidebar],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined,
                  color: AppColors.goldAccent, size: 20),
              const SizedBox(width: 8),
              Text('Comisión del día',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            money.format(data.commission),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Mini(label: 'Completados', value: '${data.completedCount}'),
              _divider(),
              _Mini(label: 'Citas', value: '${data.ticketCount}'),
              _divider(),
              _Mini(label: 'Facturado', value: money.format(data.totalSales)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 28,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 12),
      );
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.money});

  final CommissionItem item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = DateFormat('HH:mm').format(item.startTime);
    final color = _statusColor(item.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(time,
                  style: TextStyle(
                      color: cs.onSurface, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_statusLabel(item.status),
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.clientName,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(item.servicesLabel,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (item.ticketCode != null) ...[
                  const SizedBox(height: 2),
                  Text(item.ticketCode!,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.isCompleted ? money.format(item.commission) : '—',
                style: const TextStyle(
                    color: AppColors.goldAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text('comisión',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 10)),
              const SizedBox(height: 4),
              Text(money.format(item.totalPrice),
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String s) => switch (s.toLowerCase()) {
        'completed' => AppColors.statusFinalizado,
        'cancelled' => AppColors.statusCancelado,
        'in_service' || 'in_progress' => AppColors.statusEnServicio,
        'confirmed' => AppColors.statusAtendido,
        'waiting' => AppColors.statusEnEspera,
        _ => AppColors.statusSinEstado,
      };

  String _statusLabel(String s) => switch (s.toLowerCase()) {
        'completed' => 'Hecho',
        'cancelled' => 'Cancelado',
        'in_service' || 'in_progress' => 'En curso',
        'confirmed' => 'Confirmado',
        'waiting' => 'En espera',
        _ => 'Pendiente',
      };
}
