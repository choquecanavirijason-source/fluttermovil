/// Fila de cliente alineada con `GET /api/clients/`.
/// Campos no expuestos por la API (fecha, tipo de ojo) quedan vacíos hasta que existan en backend.
class ClientListItem {
  final int id;
  final String displayName;
  final String phone;

  const ClientListItem({
    required this.id,
    required this.displayName,
    this.phone = '',
  });

  factory ClientListItem.fromApi(Map<String, dynamic> m) {
    final name = (m['name'] as String?)?.trim() ?? '';
    final last = (m['last_name'] as String?)?.trim() ?? '';
    var dn = '$name $last'.trim();
    if (dn.isEmpty) {
      dn = 'Cliente #${m['id']}';
    }
    return ClientListItem(
      id: (m['id'] as num).toInt(),
      displayName: dn,
      phone: (m['phone'] as String?)?.trim() ?? '',
    );
  }

  /// Sin dato en API por ahora.
  String get fechaUltimaVisita => '';

  /// Sin dato en API por ahora (tipo de ojo / estilo).
  String get tipoOjo => '';
}
