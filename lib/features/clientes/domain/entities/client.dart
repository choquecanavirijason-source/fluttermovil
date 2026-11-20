import '../../data/models/client_dto.dart';

class Client {
  const Client({
    required this.id,
    required this.displayName,
    this.phone = '',
    this.email = '',
    this.visitCount = 0,
  });

  final int id;
  final String displayName;
  final String phone;
  final String email;
  final int visitCount;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = parts.first;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }

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
      visitCount: d.visitCount,
    );
  }
}
