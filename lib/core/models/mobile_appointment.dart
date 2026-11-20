class MobileAppointment {
  final int id;
  final int? clientId;
  final String ticketCode;
  final bool isIa;
  final String status;
  final String? startTime;
  final String clientDisplayName;
  final String primaryServiceName;
  final String servicesSummary;
  final String? branchName;

  /// Alergias de la clienta a algún producto (texto libre); null si no tiene.
  final String? clientAllergies;

  const MobileAppointment({
    required this.id,
    this.clientId,
    required this.ticketCode,
    required this.isIa,
    required this.status,
    required this.startTime,
    required this.clientDisplayName,
    required this.primaryServiceName,
    required this.servicesSummary,
    required this.branchName,
    this.clientAllergies,
  });

  factory MobileAppointment.fromApi(Map<String, dynamic> json) {
    final client = json['client'] is Map
        ? Map<String, dynamic>.from(json['client'] as Map)
        : null;
    // Alergias de ESTA atención: la API ya elige las del ticket (clienta de
    // mostrador) o las de la ficha; se cae a la ficha si el servidor es anterior.
    final allergiesRaw = (json['ticket_allergies'] ?? client?['allergies'])
            ?.toString()
            .trim() ??
        '';
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
      clientId: (client?['id'] as num?)?.toInt(),
      ticketCode: json['ticket_code']?.toString() ?? '#${json['id']}',
      isIa: json['is_ia'] == true,
      status: json['status']?.toString() ?? '',
      startTime: json['start_time']?.toString(),
      clientDisplayName: clientDisplayName.isEmpty ? 'Cliente' : clientDisplayName,
      primaryServiceName: primaryServiceName,
      servicesSummary: servicesSummary,
      branchName: branch?['name']?.toString(),
      clientAllergies: allergiesRaw.isEmpty ? null : allergiesRaw,
    );
  }
}
