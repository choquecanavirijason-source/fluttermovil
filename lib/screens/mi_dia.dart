import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import '../core/models/daily_work.dart';
import '../core/services/commission_service.dart';
import '../core/theme/app_theme.dart';

const Color _kBrand = AppColors.brand;
const Color _kBrandDark = AppColors.brandDark;
const Color _kGold = AppColors.gold;

/// "Mi día": calendario + lo que hizo la operaria y su comisión del día.
class MiDiaScreen extends StatefulWidget {
  const MiDiaScreen({super.key});

  @override
  State<MiDiaScreen> createState() => _MiDiaScreenState();
}

class _MiDiaScreenState extends State<MiDiaScreen> {
  static const _weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const _monthNames = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  DateTime _selectedDate = _dateOnly(DateTime.now());
  late DateTime _weekStart; // lunes de la semana visible

  int? _professionalId;
  bool _loading = true;
  String? _error;
  DailyWork? _work;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(_selectedDate);
    _init();
  }

  DateTime _mondayOf(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return _dateOnly(monday);
  }

  Future<void> _init() async {
    final id = await CommissionService.resolveProfessionalId();
    if (!mounted) return;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'No se pudo identificar tu usuario. Vuelve a iniciar sesión.';
      });
      return;
    }
    _professionalId = id;
    await _load();
  }

  Future<void> _load() async {
    final id = _professionalId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final work = await CommissionService.fetchDay(
        date: _selectedDate,
        professionalId: id,
        branchId: ApiConfig.defaultBranchId,
      );
      if (!mounted) return;
      setState(() {
        _work = work;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _selectDate(DateTime d) {
    final date = _dateOnly(d);
    setState(() {
      _selectedDate = date;
      _weekStart = _mondayOf(date);
    });
    _load();
  }

  Future<void> _pickFromCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _kBrand),
        ),
        child: child!,
      ),
    );
    if (picked != null) _selectDate(picked);
  }

  String _money(double v) => 'Bs ${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mi día',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Elegir fecha',
            onPressed: _pickFromCalendar,
            icon: const Icon(Icons.calendar_month),
          ),
        ],
      ),
      body: Column(
        children: [
          _calendarStrip(),
          Expanded(
            child: RefreshIndicator(
              color: _kBrand,
              onRefresh: _load,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarStrip() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final monthLabel =
        '${_monthNames[_selectedDate.month - 1]} ${_selectedDate.year}';
    return Container(
      color: _kBrand,
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setState(() =>
                    _weekStart = _weekStart.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Text(
                monthLabel[0].toUpperCase() + monthLabel.substring(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              IconButton(
                onPressed: () => setState(() =>
                    _weekStart = _weekStart.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(child: _dayCell(days[i], _weekdayLabels[i])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day, String weekday) {
    final isSelected = _dateOnly(day) == _selectedDate;
    final isToday = _dateOnly(day) == _dateOnly(DateTime.now());
    final isFuture = _dateOnly(day).isAfter(_dateOnly(DateTime.now()));
    return GestureDetector(
      onTap: isFuture ? null : () => _selectDate(day),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              weekday,
              style: TextStyle(
                color: isSelected ? _kBrand : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                color: isSelected
                    ? _kBrand
                    : isFuture
                        ? Colors.white38
                        : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday && !isSelected ? _kGold : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kBrand));
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.cloud_off, size: 46, color: Colors.grey),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent)),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kBrand),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }

    final work = _work;
    final items = work?.items ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (work != null) _summaryCard(work.summary),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text('Servicios del día',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _kBrandDark)),
            const Spacer(),
            Text('${items.length}',
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.event_busy,
                      size: 46, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text('No registraste servicios este día.',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          )
        else
          ...items.map(_itemCard),
      ],
    );
  }

  Widget _summaryCard(DailyWorkSummary s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kBrand, _kBrandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kBrand.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, color: _kGold, size: 20),
              const SizedBox(width: 8),
              Text('Comisión del día',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _money(s.commission),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _miniStat('Completados', '${s.completedCount}'),
              _divider(),
              _miniStat('Citas', '${s.ticketCount}'),
              _divider(),
              _miniStat('Facturado', _money(s.totalSales)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 30,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 12),
      );

  Widget _itemCard(DailyWorkItem it) {
    final time =
        '${it.startTime.hour.toString().padLeft(2, '0')}:${it.startTime.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(time,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: _kBrandDark)),
              const SizedBox(height: 6),
              _StatusBadge(status: it.status),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.clientName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(it.servicesSummary,
                    style:
                        TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                if (it.ticketCode != null) ...[
                  const SizedBox(height: 2),
                  Text(it.ticketCode!,
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 11.5)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                it.isCompleted ? _money(it.commission) : '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: _kGold, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text('comisión',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 10.5)),
              const SizedBox(height: 4),
              Text(_money(it.totalPrice),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    late Color color;
    late String label;
    switch (s) {
      case 'completed':
        color = const Color(0xFF2E7D32);
        label = 'Hecho';
        break;
      case 'cancelled':
        color = Colors.redAccent;
        label = 'Cancelado';
        break;
      case 'in_service':
      case 'in_progress':
        color = Colors.blue;
        label = 'En curso';
        break;
      case 'confirmed':
        color = Colors.teal;
        label = 'Confirmado';
        break;
      case 'waiting':
        color = Colors.orange;
        label = 'En espera';
        break;
      default:
        color = Colors.grey;
        label = 'Pendiente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}
