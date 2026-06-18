import 'entities/daily_commission.dart';

abstract class ComisionesRepository {
  Future<DailyCommission> day({
    required DateTime date,
    required int professionalId,
    int? branchId,
  });
}
