import '../../data/models/client_dto.dart';

class Client {
  const Client({
    required this.id,
    required this.displayName,
    this.phone = '',
    this.email = '',
  });

  final int id;
  final String displayName;
  final String phone;
  final String email;

  factory Client.fromDto(ClientDto d) {
    final name = d.name.trim();
    final last = (d.lastName ?? '').trim();
    var dn = '$name $last'.trim();
    if (dn.isEmpty) dn = 'Cliente #${d.id}';
    return Client(
      id: d.id,
      displayName: dn,
      phone: (d.phone ?? '').trim(),
      email: (d.email ?? '').trim(),
    );
  }
}
