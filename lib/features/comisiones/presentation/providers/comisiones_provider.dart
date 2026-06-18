import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env.dart';
import '../../../../core/error/api_exception.dart';
import '../../../auth/presentation/providers/auth_state_provider.dart';
import '../../data/comisiones_repository_impl.dart';
import '../../domain/entities/daily_commission.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Fecha seleccionada en la pantalla de comisión.
final selectedCommissionDateProvider = StateProvider<DateTime>(
  (ref) => _dateOnly(DateTime.now()),
);

/// Trabajo + comisión de la operaria para [date].
final dailyCommissionProvider =
    FutureProvider.autoDispose.family<DailyCommission, DateTime>((ref, date) {
  final user = ref.watch(authUserProvider);
  if (user == null) {
    throw const ApiException(message: 'Sesión no disponible.');
  }
  return ref.read(comisionesRepositoryProvider).day(
        date: date,
        professionalId: user.id,
        branchId: Env.defaultBranchId,
      );
});
