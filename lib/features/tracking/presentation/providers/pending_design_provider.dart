import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/saved_tryon_design.dart';

/// Diseño guardado que el probador debe aplicar al abrirse ("Aplicar
/// diseño" desde la ficha de la clienta). El probador lo consume y lo vacía.
final pendingTryOnDesignProvider = StateProvider<SavedTryOnDesign?>(
  (ref) => null,
);
