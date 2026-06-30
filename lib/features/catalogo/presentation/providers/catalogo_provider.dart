import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../native_eye_tracking_service.dart';
import '../../data/catalog_repository_impl.dart';
import '../../domain/entities/catalog_item.dart';

/// Lista completa del catálogo por tipo (sin filtro de ojo).
final catalogListProvider =
    FutureProvider.autoDispose.family<List<CatalogItem>, CatalogKind>(
  (ref, kind) => ref.read(catalogRepositoryProvider).list(kind),
);

/// Lista de catálogo filtrada en tiempo real por la forma de ojo detectada.
///
/// Comportamiento:
/// - Emite **todos** los items inmediatamente (sin esperar detección).
/// - Cada vez que la cámara clasifica una forma de ojo distinta,
///   re-emite solo los items cuyo [CatalogItem.tipoOjoCompatible] coincide.
///   - Items con [tipoOjoCompatible] == null siempre se incluyen (universales).
///   - Si el filtro no produce resultados, se devuelve la lista completa.
final filteredCatalogProvider =
    StreamProvider.autoDispose.family<List<CatalogItem>, CatalogKind>(
  (ref, kind) async* {
    final service = ref.read(nativeEyeTrackingServiceProvider);

    // Carga única del catálogo completo — reutiliza la caché de catalogListProvider.
    final allItems = await ref.watch(catalogListProvider(kind).future);

    // Emite la lista completa antes de cualquier detección de forma de ojo.
    yield allItems;

    // Actualiza en tiempo real conforme la cámara clasifica la forma del ojo.
    // eyeShapeStream solo emite cuando el valor *cambia* y nunca emite 'UNKNOWN'.
    await for (final shape in service.eyeShapeStream) {
      final shapeLower = shape.toLowerCase();

      final filtered = allItems.where((item) {
        final compat = item.tipoOjoCompatible?.toLowerCase();
        // null  → item universal (compatible con cualquier ojo)
        // valor → debe coincidir con la forma detectada
        return compat == null || compat == shapeLower;
      }).toList();

      // Evita pantalla vacía: si ningún item coincide, muestra todo.
      yield filtered.isEmpty ? allItems : filtered;
    }
  },
);
