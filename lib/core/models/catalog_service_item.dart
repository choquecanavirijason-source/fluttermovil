/// Servicio para catálogo (pantalla Servicios).
class CatalogServiceItem {
  final int id;
  final String name;
  final String? price;
  final String? imageUrl;

  const CatalogServiceItem({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
  });

  factory CatalogServiceItem.fromServiceMap(Map<String, dynamic> m) {
    final price = m['price']?.toString() ??
        m['cost']?.toString() ??
        m['base_price']?.toString();
    final imageUrl = m['image_url']?.toString() ??
        m['imagen']?.toString() ??
        m['image']?.toString();
    return CatalogServiceItem(
      id: (m['id'] as num?)?.toInt() ?? 0,
      name: m['name']?.toString() ?? 'Servicio',
      price: price,
      imageUrl: imageUrl != null && imageUrl.isNotEmpty ? imageUrl : null,
    );
  }
}
