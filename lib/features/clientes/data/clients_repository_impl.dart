import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../domain/clients_repository.dart';
import '../domain/entities/client.dart';
import 'clients_api.dart';

class ClientsRepositoryImpl implements ClientsRepository {
  ClientsRepositoryImpl(this._api);

  final ClientsApi _api;

  @override
  Future<List<Client>> list({String? search}) async {
    final dtos = await _api.list(search: search);
    return dtos.map(Client.fromDto).toList();
  }
}

final clientsRepositoryProvider = Provider<ClientsRepository>((ref) {
  return ClientsRepositoryImpl(ClientsApi(ref.watch(dioProvider)));
});
