import 'dart:convert';

import '../config/api_config.dart';
import '../models/daily_work.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Trabajo y comisión de la operaria por día (`/api/reports/daily-closing`).
class CommissionService {
  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Asegura tener el `id` de la operaria logueada (= `professional_id`).
  /// Si la sesión se restauró desde disco, lo recupera vía `/auth/me`.
  static Future<int?> resolveProfessionalId() async {
    final current = AuthSession.currentUser;
    if (current != null && current.id > 0) return current.id;
    try {
      final user = await AuthService().fetchCurrentUser();
      return user.id > 0 ? user.id : null;
    } catch (_) {
      return null;
    }
  }

  static Future<DailyWork> fetchDay({
    required DateTime date,
    required int professionalId,
    int? branchId,
  }) async {
    final body = await ApiClient.get(
      ApiConfig.reportsDailyClosing,
      queryParameters: {
        'date': _ymd(date),
        'professional_id': professionalId,
        'branch_id': ?branchId,
      },
    );

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Respuesta de cierre diario inválida');
    }

    final rawItems = decoded['items'];
    final items = <DailyWorkItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(DailyWorkItem.fromApi(Map<String, dynamic>.from(e)));
        }
      }
    }
    items.sort((a, b) => a.startTime.compareTo(b.startTime));

    return DailyWork(
      date: date,
      items: items,
      summary: DailyWorkSummary.fromItems(items),
    );
  }
}
