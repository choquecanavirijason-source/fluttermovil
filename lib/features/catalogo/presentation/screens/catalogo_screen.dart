import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/organisms/async_value_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/catalog_item.dart';
import '../providers/catalogo_provider.dart';

class CatalogoScreen extends StatelessWidget {
  const CatalogoScreen({super.key, this.initialKind = CatalogKind.lashDesign});

  final CatalogKind initialKind;

  static const _kinds = CatalogKind.values;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _kinds.length,
      initialIndex: _kinds.indexOf(initialKind),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Modelos de pestañas'),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: AppColors.goldAccent,
            tabAlignment: TabAlignment.start,
            tabs: [for (final k in _kinds) Tab(text: k.label)],
          ),
        ),
        body: TabBarView(
          children: [for (final k in _kinds) _CatalogTab(kind: k)],
        ),
      ),
    );
  }
}

class _CatalogTab extends ConsumerWidget {
  const _CatalogTab({required this.kind});

  final CatalogKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(catalogListProvider(kind));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(catalogListProvider(kind)),
      child: AsyncValueView<List<CatalogItem>>(
        value: async,
        onRetry: () => ref.invalidate(catalogListProvider(kind)),
        builder: (items) {
          if (items.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 120),
                Icon(Icons.style_outlined,
                    size: 52,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Center(
                  child: Text('No hay ${kind.label.toLowerCase()}.',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ],
            );
          }
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.74,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _CatalogCard(item: items[i]),
          );
        },
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _DetailSheet(item: item),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _CatalogImage(item: item)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: cs.onSurface)),
                  if (item.description != null) ...[
                    const SizedBox(height: 3),
                    Text(item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogImage extends StatelessWidget {
  const _CatalogImage({required this.item, this.fit = BoxFit.cover});

  final CatalogItem item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl;
    if (url == null) return const _ImageFallback();
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: double.infinity,
      placeholder: (context, _) => const ColoredBox(
        color: Color(0x22D4A517),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: AppColors.goldAccent),
          ),
        ),
      ),
      errorWidget: (context, _, __) => const _ImageFallback(),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.goldAccent.withValues(alpha: 0.12),
      child: const Center(
        child: Icon(Icons.remove_red_eye_outlined,
            color: AppColors.goldAccent, size: 40),
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _CatalogImage(item: item),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.goldAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(item.kind.label,
                        style: const TextStyle(
                            color: AppColors.goldAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 10),
                  Text(item.name,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface)),
                  if (item.description != null) ...[
                    const SizedBox(height: 10),
                    Text(item.description!,
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
