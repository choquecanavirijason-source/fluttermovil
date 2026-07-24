import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Probador/features/catalogo/domain/entities/catalog_item.dart';
import 'package:Probador/features/catalogo/presentation/providers/catalogo_provider.dart';

/// Bottom sheet para elegir manualmente el "tipo de ojo" (pill superior de
/// [EyeTrackingPage]). Si [preloadedItems] viene con datos, los usa
/// directamente (evita un refetch cuando la página ya los precargó); si no,
/// los pide al catálogo.
class EyeTypePickerSheet extends ConsumerWidget {
  final CatalogItem? selected;
  final ValueChanged<CatalogItem> onSelect;
  final List<CatalogItem>? preloadedItems;

  const EyeTypePickerSheet({
    super.key,
    required this.selected,
    required this.onSelect,
    this.preloadedItems,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = preloadedItems != null
        ? AsyncValue.data(preloadedItems!)
        : ref.watch(catalogListProvider(CatalogKind.eyeType));

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.75,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tipo de ojo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: asyncItems.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error al cargar: $e')),
              data: (items) => ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final isSelected = selected?.id == item.id;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    leading: item.hasImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: item.imageUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => const _EyeTypeIcon(),
                            ),
                          )
                        : const _EyeTypeIcon(),
                    title: Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: item.description != null
                        ? Text(
                            item.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFF094732),
                          )
                        : null,
                    onTap: () => onSelect(item),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EyeTypeIcon extends StatelessWidget {
  const _EyeTypeIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF094732).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.remove_red_eye_outlined,
        color: Color(0xFF094732),
        size: 22,
      ),
    );
  }
}
