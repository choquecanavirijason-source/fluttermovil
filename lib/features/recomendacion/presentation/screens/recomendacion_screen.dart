import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/organisms/async_value_view.dart';
import '../../../../core/recommendation/eye_shape_analyzer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../recommendation_args.dart';
import '../../../catalogo/domain/entities/catalog_item.dart';
import '../../domain/lash_recommendation.dart';
import '../../domain/lash_recommender.dart';
import '../providers/recomendacion_provider.dart';
import '../widgets/save_tracking_sheet.dart';

class RecomendacionScreen extends ConsumerWidget {
  const RecomendacionScreen({super.key, required this.args});

  final RecommendationArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recommendationCatalogProvider);
    final analysis = args.analysis;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.brandPrimary,
            foregroundColor: Colors.white,
            title: const Text('Recomendación IA'),
            flexibleSpace: FlexibleSpaceBar(
              background: _PhotoHeader(
                bytes: args.photoPngBytes,
                mirror: args.mirrorPhoto,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AsyncValueView<Map<CatalogKind, List<CatalogItem>>>(
              value: async,
              onRetry: () => ref.invalidate(recommendationCatalogProvider),
              builder: (catalog) {
                final reco = LashRecommender.build(
                  analysis: analysis,
                  eyeTypes: catalog[CatalogKind.eyeType] ?? const [],
                  designs: catalog[CatalogKind.lashDesign] ?? const [],
                  effects: catalog[CatalogKind.effect] ?? const [],
                  volumes: catalog[CatalogKind.volume] ?? const [],
                );
                return _Content(analysis: analysis, reco: reco);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.analysis, required this.reco});

  final EyeAnalysis analysis;
  final LashRecommendation reco;

  Future<void> _openSave(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaveTrackingSheet(
        reco: reco,
        shapeName: analysis.shape.catalogName,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Recomendación guardada en la ficha del cliente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 18, 16, 32 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.goldAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.remove_red_eye,
                    color: AppColors.goldAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Forma detectada: ${analysis.shape.catalogName}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(analysis.shape.description,
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if (!analysis.reliable)
            _notice(
              context,
              'No se detectó el rostro con claridad. La sugerencia es aproximada; '
              'vuelve a capturar centrando la mirada.',
              warning: true,
            ),
          if (reco.reason.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.brandPrimary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.goldAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(reco.reason,
                        style: TextStyle(
                            fontSize: 14, height: 1.4, color: cs.onSurface)),
                  ),
                ],
              ),
            ),
          ],
          _section(context, 'Diseños recomendados', reco.designs),
          _section(context, 'Efecto', reco.effects),
          _section(context, 'Volumen', reco.volumes),
          if (reco.eyeType != null)
            _section(context, 'Tu tipo de ojo', [reco.eyeType!]),
          if (!reco.hasAnyItem)
            _notice(
              context,
              'Aún no hay modelos en el catálogo. Pide al administrador que cargue '
              'los diseños (con imagen) para ver sugerencias aquí.',
            ),
          if (reco.hasAnyItem) ...[
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openSave(context),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar en ficha del cliente'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Sugerencia generada en el dispositivo a partir de la forma del ojo. '
            'Es orientativa; la operaria decide el diseño final.',
            style: TextStyle(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _notice(BuildContext context, String text, {bool warning = false}) {
    final color = warning ? AppColors.statusEnEspera : AppColors.statusReserva;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warning ? Icons.info_outline : Icons.inventory_2_outlined,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }

  Widget _section(
      BuildContext context, String title, List<CatalogItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface)),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _RecoCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _RecoCard extends StatelessWidget {
  const _RecoCard({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = item.imageUrl;
    return SizedBox(
      width: 130,
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: url == null
                  ? _fallback()
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (context, _) => const ColoredBox(
                        color: Color(0x22D4A517),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.goldAccent),
                          ),
                        ),
                      ),
                      errorWidget: (context, _, __) => _fallback(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: cs.onSurface)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.goldAccent.withValues(alpha: 0.12),
        child: const Center(
          child: Icon(Icons.remove_red_eye_outlined,
              color: AppColors.goldAccent, size: 32),
        ),
      );
}

class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.bytes, required this.mirror});

  final Uint8List? bytes;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    if (bytes == null || bytes!.isEmpty) {
      return const ColoredBox(
        color: AppColors.brandPrimary,
        child: Center(
          child: Icon(Icons.face_retouching_natural,
              color: Colors.white24, size: 80),
        ),
      );
    }
    Widget img = Image.memory(bytes!, fit: BoxFit.cover);
    if (mirror) {
      img = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
        child: img,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        img,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),
      ],
    );
  }
}
