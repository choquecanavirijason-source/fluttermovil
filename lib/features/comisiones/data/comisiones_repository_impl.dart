import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/dio_client.dart';
import '../domain/comisiones_repository.dart';
import '../domain/entities/daily_commission.dart';
import 'daily_closing_api.dart';

class ComisionesRepositoryImpl implements ComisionesRepository {
  ComisionesRepositoryImpl(this._api);

  final DailyClosingApi _api;

  @override
  Future<DailyCommission> day({
    required DateTime date,
    required int professionalId,
    int? branchId,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final dto = await _api.getClosing(
      date: dateStr,
      professionalId: professionalId,
      branchId: branchId,
    );
    return DailyCommission.fromDto(dto, date);
  }
}

final comisionesRepositoryProvider = Provider<ComisionesRepository>((ref) {
  return ComisionesRepositoryImpl(DailyClosingApi(ref.watch(dioProvider)));
});
