import 'dart:convert';

import '../config/api_config.dart';
import '../models/catalog_service_item.dart';
import '../models/mobile_appointment.dart';
import 'api_client.dart';

class AgendaService {
  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Tickets móviles disponibles con `is_ia == true`.
  static Future<List<MobileAppointment>> fetchMobileIaTickets({
    int? branchId,
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    int limit = 100,
  }) async {
    final now = DateTime.now();
    final start = startDate ?? now.subtract(const Duration(days: 7));
    final end = endDate ?? now.add(const Duration(days: 30));

    final qp = <String, dynamic>{
      'skip': 0,
      'limit': limit,
      'start_date': _ymd(start),
      'end_date': _ymd(end),
      'branch_id': ?branchId,
      'search': ?(search != null && search.trim().isNotEmpty ? search.trim() : null),
    };

    final body = await ApiClient.get(
      ApiConfig.agendaAppointmentsMobileAvailable,
      queryParameters: qp,
    );

    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Respuesta de citas móviles inválida');
    }

    return decoded
        .map((e) => MobileAppointment.fromApi(Map<String, dynamic>.from(e as Map)))
        .where((a) => a.isIa)
        .toList();
  }

  /// Intenta listar servicios con categoría móvil vía `GET /api/services/`.
  /// Si el backend no expone la ruta, deduplica desde citas móviles disponibles.
  static Future<List<CatalogServiceItem>> fetchMobileServices({
    int? branchId,
    int limitAppointments = 300,
  }) async {
    try {
      final body = await ApiClient.get(
        ApiConfig.servicesList,
        queryParameters: {
          'skip': 0,
          'limit': 500,
        },
      );
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('Lista de servicios inválida');
      }
      final out = <CatalogServiceItem>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final cat = m['category'] is Map
            ? Map<String, dynamic>.from(m['category'] as Map)
            : null;
        final isMobile = cat?['is_mobile'] == true;
        if (!isMobile) continue;
        out.add(CatalogServiceItem.fromServiceMap(m));
      }
      if (out.isEmpty) {
        return _mobileServicesFromAppointments(
          branchId: branchId,
          limit: limitAppointments,
        );
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } catch (_) {
      return _mobileServicesFromAppointments(
        branchId: branchId,
        limit: limitAppointments,
      );
    }
  }

  static Future<List<CatalogServiceItem>> _mobileServicesFromAppointments({
    int? branchId,
    required int limit,
  }) async {
    final now = DateTime.now();
    final qp = <String, dynamic>{
      'skip': 0,
      'limit': limit,
      'start_date': _ymd(now.subtract(const Duration(days: 60))),
      'end_date': _ymd(now.add(const Duration(days: 60))),
      'branch_id': ?branchId,
    };

    final body = await ApiClient.get(
      ApiConfig.agendaAppointmentsMobileAvailable,
      queryParameters: qp,
    );

    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Respuesta de citas móviles inválida');
    }

    final byId = <int, CatalogServiceItem>{};
    for (final e in decoded) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      final service = map['service'] is Map
          ? Map<String, dynamic>.from(map['service'] as Map)
          : null;
      if (service != null) {
        final id = (service['id'] as num?)?.toInt() ?? 0;
        if (id != 0) {
          byId[id] = CatalogServiceItem.fromServiceMap(service);
        }
      }
      final services = map['services'];
      if (services is List) {
        for (final x in services) {
          if (x is! Map) continue;
          final sm = Map<String, dynamic>.from(x);
          final id = (sm['id'] as num?)?.toInt() ?? 0;
          if (id == 0) continue;
          byId.putIfAbsent(
            id,
            () => CatalogServiceItem.fromServiceMap(sm),
          );
        }
      }
    }

    final list = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
