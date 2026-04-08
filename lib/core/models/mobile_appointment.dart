class MobileAppointment {
  final int id;
  final String ticketCode;
  final bool isIa;
  final String status;
  final String? startTime;
  final String clientDisplayName;
  final String primaryServiceName;
  final String servicesSummary;
  final String? branchName;

  const MobileAppointment({
    required this.id,
    required this.ticketCode,
    required this.isIa,
    required this.status,
    required this.startTime,
    required this.clientDisplayName,
    required this.primaryServiceName,
    required this.servicesSummary,
    required this.branchName,
  });

  factory MobileAppointment.fromApi(Map<String, dynamic> json) {
    final client = json['client'] is Map
        ? Map<String, dynamic>.from(json['client'] as Map)
        : null;
    final name = client?['name']?.toString().trim() ?? '';
    final last = client?['last_name']?.toString().trim() ?? '';
    final clientDisplayName = [name, last].where((s) => s.isNotEmpty).join(' ');

    final service = json['service'] is Map
        ? Map<String, dynamic>.from(json['service'] as Map)
        : null;
    final primaryServiceName = service?['name']?.toString() ?? '—';

    final servicesList = json['services'];
    final names = <String>[];
    if (servicesList is List) {
      for (final e in servicesList) {
        if (e is Map) {
          final n = e['name']?.toString();
          if (n != null && n.isNotEmpty) names.add(n);
        }
      }
    }
    final servicesSummary =
        names.isNotEmpty ? names.join(', ') : primaryServiceName;

    final branch = json['branch'] is Map
        ? Map<String, dynamic>.from(json['branch'] as Map)
        : null;

    return MobileAppointment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ticketCode: json['ticket_code']?.toString() ?? '#${json['id']}',
      isIa: json['is_ia'] == true,
      status: json['status']?.toString() ?? '',
      startTime: json['start_time']?.toString(),
      clientDisplayName: clientDisplayName.isEmpty ? 'Cliente' : clientDisplayName,
      primaryServiceName: primaryServiceName,
      servicesSummary: servicesSummary,
      branchName: branch?['name']?.toString(),
    );
  }
}
