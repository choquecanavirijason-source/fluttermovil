import 'entities/client.dart';

abstract class ClientsRepository {
  Future<List<Client>> list({String? search});
}
