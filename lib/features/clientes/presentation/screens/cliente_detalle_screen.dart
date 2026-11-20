import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/presentation/organisms/async_value_view.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../tracking/domain/entities/saved_tryon_design.dart';
import '../../../tracking/domain/entities/tracking_record.dart';
import '../../../tracking/presentation/providers/pending_design_provider.dart';
import '../../../tracking/presentation/providers/tracking_history_provider.dart';
import '../../domain/entities/client.dart';
import '../providers/clientes_provider.dart';

/// Ficha del cliente: datos + historial de aplicaciones (Tracking).
class ClienteDetalleScreen extends ConsumerWidget {
  const ClienteDetalleScreen({super.key, required this.client});

  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientTrackingProvider(client.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Ficha de la clienta')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(clientTrackingProvider(client.id)),
        child: AsyncValueView<List<TrackingRecord>>(
          value: async,
          onRetry: () => ref.invalidate(clientTrackingProvider(client.id)),
          builder: (records) {
            final eyeType = records
                .map((r) => r.eyeType)
                .firstWhere(
                  (e) => e != null && e.isNotEmpty,
                  orElse: () => null,
                );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                28 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _ClientCard(client: client, eyeType: eyeType),
                const SizedBox(height: 18),
                Text(
                  'Aplicaciones anteriores',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                if (records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.history,
                            size: 44,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Sin aplicaciones registradas.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...records.map(
                    (r) => _ApplicationTile(
                      record: r,
                      onApply: r.design == null
                          ? null
                          : () => _applyDesign(context, ref, r.design!),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Abre el probador con esta clienta asignada y el diseño guardado.
  void _applyDesign(
    BuildContext context,
    WidgetRef ref,
    SavedTryOnDesign design,
  ) {
    ref.read(pendingTryOnDesignProvider.notifier).state = design;
    ref.read(sessionClientProvider.notifier).state = client;
    context.push(AppRoutes.selection);
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
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            client.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (client.phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              client.phone,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
          if (eyeType != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.goldAccent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                eyeType!,
                style: const TextStyle(
                  color: AppColors.goldAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({required this.record, this.onApply});

  final TrackingRecord record;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final design = record.design;
    final dateLabel = record.date != null
        ? DateFormat('dd/MM/yyyy').format(record.date!)
        : 'Sin fecha';
    final title = design?.styleName ?? record.lashDesign ?? record.effect;

    final chips = <Widget>[
      if (design?.lengthName != null)
        _OptionChip(icon: Icons.straighten_rounded, text: design!.lengthName!),
      if (design?.techniqueName != null)
        _OptionChip(icon: Icons.grain_rounded, text: design!.techniqueName!),
      if (design?.thicknessName != null)
        _OptionChip(
          icon: Icons.line_weight_rounded,
          text: design!.thicknessName!,
        ),
      if (design != null)
        _OptionChip(
          swatch: _hexColor(design.colorHex ?? '#111111'),
          text: design.colorName ?? 'Negro',
        ),
      if (design == null && record.volume != null)
        _OptionChip(icon: Icons.grain_rounded, text: record.volume!),
      if (record.eyeType != null)
        _OptionChip(icon: Icons.visibility_outlined, text: record.eyeType!),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.goldAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.goldAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? 'Aplicación',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          if (chips.isEmpty && record.notes == null) ...[
            const SizedBox(height: 8),
            Text(
              'Sin detalles registrados.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
          if (record.notes != null)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  'Notas de la consulta',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.notes!.replaceAll(' | ', '\n'),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          if (onApply != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onApply,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.remove_red_eye_outlined, size: 19),
                label: const Text(
                  'Aplicar diseño en el probador',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _hexColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.text, this.icon, this.swatch});

  final String text;
  final IconData? icon;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatch != null)
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outline, width: 0.8),
              ),
            )
          else if (icon != null)
            Icon(icon, size: 14, color: AppColors.brandPrimary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
