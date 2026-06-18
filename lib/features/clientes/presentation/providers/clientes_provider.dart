import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/clients_repository_impl.dart';
import '../../domain/entities/client.dart';

/// Texto de búsqueda activo (actualizado con debounce desde la UI).
final clientSearchProvider = StateProvider<String>((ref) => '');

/// Lista de clientes para la búsqueda actual.
final clientsListProvider =
    FutureProvider.autoDispose<List<Client>>((ref) async {
  final query = ref.watch(clientSearchProvider);
  return ref.read(clientsRepositoryProvider).list(search: query);
});
