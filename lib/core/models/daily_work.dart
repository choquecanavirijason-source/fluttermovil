/// Un servicio/cita realizado en el día (deriva de `DailyClosingItem` del backend).
class DailyWorkItem {
  final int appointmentId;
  final String? ticketCode;
  final String clientName;
  final List<String> serviceNames;
  final DateTime startTime;
  final String status;
  final double totalPrice;
  final double commission;
  final double commissionRate;
  final bool isPaid;

  const DailyWorkItem({
    required this.appointmentId,
    required this.ticketCode,
    required this.clientName,
    required this.serviceNames,
    required this.startTime,
    required this.status,
    required this.totalPrice,
    required this.commission,
    required this.commissionRate,
    required this.isPaid,
  });

  bool get isCompleted => status.toLowerCase() == 'completed';

  String get servicesSummary =>
      serviceNames.isNotEmpty ? serviceNames.join(', ') : 'Servicio';

  factory DailyWorkItem.fromApi(Map<String, dynamic> m) {
    final rawServices = m['service_names'];
    final services = <String>[];
    if (rawServices is List) {
      for (final e in rawServices) {
        final s = e?.toString();
        if (s != null && s.trim().isNotEmpty) services.add(s.trim());
      }
    }

    DateTime start;
    try {
      start = DateTime.parse(m['start_time'].toString()).toLocal();
    } catch (_) {
      start = DateTime.now();
    }

    return DailyWorkItem(
      appointmentId: (m['appointment_id'] as num?)?.toInt() ?? 0,
      ticketCode: m['ticket_code']?.toString(),
      clientName: m['client_name']?.toString().trim().isNotEmpty == true
          ? m['client_name'].toString().trim()
          : 'Cliente',
      serviceNames: services,
      startTime: start,
      status: m['status']?.toString() ?? '',
      totalPrice: (m['total_price'] as num?)?.toDouble() ?? 0.0,
      commission: (m['commission'] as num?)?.toDouble() ?? 0.0,
      commissionRate: (m['commission_rate'] as num?)?.toDouble() ?? 0.0,
      isPaid: m['is_paid'] == true,
    );
  }
}

/// Resumen del día para la operaria.
class DailyWorkSummary {
  final int ticketCount; // citas totales del día
  final int completedCount;
  final double totalSales; // total facturado (solo completadas)
  final double commission; // comisión ganada (solo completadas)

  const DailyWorkSummary({
    required this.ticketCount,
    required this.completedCount,
    required this.totalSales,
    required this.commission,
  });

  /// Calcula el resumen a partir de los ítems del día.
  factory DailyWorkSummary.fromItems(List<DailyWorkItem> items) {
    var completed = 0;
    var total = 0.0;
    var commission = 0.0;
    for (final it in items) {
      if (it.isCompleted) {
        completed++;
        total += it.totalPrice;
        commission += it.commission;
      }
    }
    return DailyWorkSummary(
      ticketCount: items.length,
      completedCount: completed,
      totalSales: total,
      commission: commission,
    );
  }
}

/// Resultado del día: ítems ordenados + resumen.
class DailyWork {
  final DateTime date;
  final List<DailyWorkItem> items;
  final DailyWorkSummary summary;

  const DailyWork({
    required this.date,
    required this.items,
    required this.summary,
  });
}
