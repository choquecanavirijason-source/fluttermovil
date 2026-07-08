import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/env.dart';
import '../../../../core/models/mobile_appointment.dart';
import '../../../../core/services/agenda_service.dart';
import '../../../../core/services/local_notifications_service.dart';
import '../../../../core/storage/prefs_storage.dart';
import '../../../auth/presentation/providers/auth_state_provider.dart';

/// Sondea periódicamente las citas asignadas a la operaria logueada mientras
/// la app está en uso, y notifica (bandeja del sistema) cuando el
/// administrador le asigna una cita que no tenía antes — sin importar si el
/// cliente ya le había sido asignado previamente (una operaria puede
/// perfectamente volver a atender al mismo cliente, y eso también merece
/// aviso).
///
/// Usa `/agenda/appointments` filtrado por `professional_id` (no el listado
/// general de clientes, que es compartido por todo el salón) porque la
/// asignación ocurre a través de una cita.
///
/// El estado de "citas ya vistas" se guarda en `SharedPreferences` bajo una
/// clave por usuario (`Env.knownAppointmentIdsPrefsKey_<userId>`), para que
/// si el dispositivo lo comparten varias operarias no se mezclen ni se
/// pierdan avisos entre sesiones.
///
/// La primera vez que corre para un usuario (sin estado guardado) solo
/// registra las citas ya asignadas, sin notificar, para no generar un
/// aluvión de avisos con la agenda que ya tenía.
class NewAppointmentWatcher {
  NewAppointmentWatcher(this._ref);

  final Ref _ref;
  Timer? _timer;
  bool _checking = false;

  static const Duration _pollInterval = Duration(minutes: 3);

  /// A partir de cuántas citas nuevas en una misma pasada se agrupan en un
  /// solo aviso en vez de uno por cita (evita spam ante asignaciones masivas).
  static const int _groupNotificationThreshold = 5;

  void start() {
    if (_timer != null) return;
    unawaited(_checkOnce());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_checkOnce()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Verifica de inmediato, sin esperar al sondeo periódico — se usa cuando
  /// llega un evento en vivo por WebSocket que indica que la agenda cambió.
  void checkNow() {
    if (_timer == null) return; // no está corriendo (sin sesión / detenido)
    unawaited(_checkOnce());
  }

  static String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt);
  }

  Future<void> _checkOnce() async {
    if (_checking) return;
    final user = _ref.read(authUserProvider);
    if (user == null) return;

    _checking = true;
    try {
      final appointments = await AgendaService.fetchAssignedAppointments(
        professionalId: user.id,
        branchId: user.branchId,
      );

      final byId = <int, MobileAppointment>{
        for (final a in appointments) a.id: a,
      };
      final currentIds = byId.keys.toSet();

      final prefsKey = '${Env.knownAppointmentIdsPrefsKey}_${user.id}';
      final prefs = _ref.read(prefsStorageProvider);
      final stored = prefs.readString(prefsKey);

      if (stored == null) {
        // Primera ejecución para este usuario: solo establece la línea base.
        debugPrint(
            'NewAppointmentWatcher: primera ejecución para user ${user.id}, '
            'línea base = $currentIds (sin notificar)');
        await prefs.writeString(prefsKey, currentIds.join(','));
        return;
      }

      final knownIds = stored.isEmpty
          ? <int>{}
          : stored.split(',').map(int.parse).toSet();

      final newAppointmentIds =
          currentIds.where((id) => !knownIds.contains(id)).toList();

      debugPrint('NewAppointmentWatcher: asignadas=$currentIds '
          'conocidas=$knownIds nuevas=$newAppointmentIds');

      if (newAppointmentIds.isNotEmpty) {
        final notifications = _ref.read(localNotificationsServiceProvider);
        if (newAppointmentIds.length >= _groupNotificationThreshold) {
          await notifications.show(
            id: 0,
            title: 'Citas nuevas asignadas',
            body: '${newAppointmentIds.length} citas nuevas en tu agenda.',
          );
        } else {
          for (final id in newAppointmentIds) {
            final a = byId[id];
            final time = _formatTime(a?.startTime);
            final name = a?.clientDisplayName ?? 'Cliente';
            await notifications.show(
              id: id,
              title: 'Nueva cita asignada',
              body: time.isEmpty ? name : '$name — $time',
            );
          }
        }
      }

      await prefs.writeString(prefsKey, currentIds.join(','));
    } catch (e) {
      debugPrint('NewAppointmentWatcher._checkOnce: $e');
    } finally {
      _checking = false;
    }
  }
}

final newAppointmentWatcherProvider = Provider<NewAppointmentWatcher>((ref) {
  final watcher = NewAppointmentWatcher(ref);
  ref.onDispose(watcher.stop);
  return watcher;
});
