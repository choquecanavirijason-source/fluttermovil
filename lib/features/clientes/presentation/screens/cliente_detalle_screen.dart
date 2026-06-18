import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/presentation/organisms/async_value_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../tracking/domain/entities/tracking_record.dart';
import '../../../tracking/presentation/providers/tracking_history_provider.dart';
import '../../domain/entities/client.dart';

/// Ficha del cliente: datos + historial de aplicaciones (Tracking).
class ClienteDetalleScreen extends ConsumerWidget {
  const ClienteDetalleScreen({super.key, required this.client});

  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientTrackingProvider(client.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Seleccionar Cliente')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clientTrackingProvider(client.id)),
        child: AsyncValueView<List<TrackingRecord>>(
          value: async,
          onRetry: () => ref.invalidate(clientTrackingProvider(client.id)),
          builder: (records) {
            final eyeType = records
                .map((r) => r.eyeType)
                .firstWhere((e) => e != null && e.isNotEmpty,
                    orElse: () => null);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _ClientCard(client: client, eyeType: eyeType),
                const SizedBox(height: 18),
                Text('Aplicaciones anteriores',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 10),
                if (records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.history,
                              size: 44,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(height: 10),
                          Text('Sin aplicaciones registradas.',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                  )
                else
                  ...records.map((r) => _ApplicationTile(record: r)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.eyeType});

  final Client client;
  final String? eyeType;

  String get _initials {
    final parts = client.displayName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = parts.first;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandPrimary, AppColors.brandSidebar],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            child: Text(_initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Text(client.displayName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800)),
          if (client.phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(client.phone,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          ],
          if (eyeType != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.goldAccent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(eyeType!,
                  style: const TextStyle(
                      color: AppColors.goldAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({required this.record});

  final TrackingRecord record;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateLabel = record.date != null
        ? DateFormat('dd/MM/yyyy').format(record.date!)
        : 'Sin fecha';

    final details = <(String, String)>[
      if (record.lashDesign != null) ('Diseño', record.lashDesign!),
      if (record.effect != null) ('Efecto', record.effect!),
      if (record.volume != null) ('Volumen', record.volume!),
      if (record.eyeType != null) ('Tipo de ojo', record.eyeType!),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.event, color: AppColors.goldAccent),
          title: Text('Fecha de aplicación: $dateLabel',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isEmpty && record.notes == null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Sin detalles registrados.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final d in details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text('${d.$1}: ',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13)),
                    Expanded(
                      child: Text(d.$2,
                          style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            if (record.notes != null) ...[
              const SizedBox(height: 6),
              Text(record.notes!,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }
}
