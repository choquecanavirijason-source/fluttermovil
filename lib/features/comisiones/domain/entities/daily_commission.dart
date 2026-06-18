import '../../data/models/daily_closing_dto.dart';

/// Un servicio realizado en el día por la operaria.
class CommissionItem {
  const CommissionItem({
    required this.appointmentId,
    required this.ticketCode,
    required this.clientName,
    required this.serviceNames,
    required this.startTime,
    required this.status,
    required this.totalPrice,
    required this.commission,
    required this.isPaid,
  });

  final int appointmentId;
  final String? ticketCode;
  final String clientName;
  final List<String> serviceNames;
  final DateTime startTime;
  final String status;
  final double totalPrice;
  final double commission;
  final bool isPaid;

  bool get isCompleted => status.toLowerCase() == 'completed';
  String get servicesLabel =>
      serviceNames.isNotEmpty ? serviceNames.join(', ') : 'Servicio';

  factory CommissionItem.fromDto(DailyClosingItemDto d) {
    DateTime start;
    try {
      start = DateTime.parse(d.startTime).toLocal();
    } catch (_) {
      start = DateTime.now();
    }
    return CommissionItem(
      appointmentId: d.appointmentId,
      ticketCode: d.ticketCode,
      clientName: d.clientName.trim().isEmpty ? 'Cliente' : d.clientName.trim(),
      serviceNames: d.serviceNames,
      startTime: start,
      status: d.status,
      totalPrice: d.totalPrice,
      commission: d.commission,
      isPaid: d.isPaid,
    );
  }
}

/// Resumen + detalle del día para la operaria.
class DailyCommission {
  const DailyCommission({
    required this.date,
    required this.items,
    required this.ticketCount,
    required this.completedCount,
    required this.totalSales,
    required this.commission,
  });

  final DateTime date;
  final List<CommissionItem> items;
  final int ticketCount;
  final int completedCount;
  final double totalSales;
  final double commission;

  factory DailyCommission.fromDto(
    DailyClosingResponseDto dto,
    DateTime date,
  ) {
    final items = dto.items.map(CommissionItem.fromDto).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    var completed = 0;
    var sales = 0.0;
    var commission = 0.0;
    for (final it in items) {
      if (it.isCompleted) {
        completed++;
        sales += it.totalPrice;
        commission += it.commission;
      }
    }
    return DailyCommission(
      date: date,
      items: items,
      ticketCount: items.length,
      completedCount: completed,
      totalSales: sales,
      commission: commission,
    );
  }
}
