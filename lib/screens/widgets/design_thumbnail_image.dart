import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Miniatura de una opción del menú de personalización (diseño/técnica/
/// efecto/grosor).
///
/// Usa [CachedNetworkImage] cuando [path] es una URL remota — los diseños
/// reales del catálogo (panel admin) traen su imagen como URL — o
/// [Image.asset] cuando es un asset local empaquetado, como siguen siendo
/// hoy las categorías que el backend todavía no expone (tech/effect/
/// thickness, ver `LashCustomizationCatalog`).
class DesignThumbnailImage extends StatelessWidget {
  const DesignThumbnailImage({
    super.key,
    required this.path,
    required this.size,
    this.color,
  });

  final String path;
  final double size;
  final Color? color;

  bool get _isNetwork => path.startsWith('http://') || path.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return _fallbackIcon();
    if (_isNetwork) {
      return CachedNetworkImage(
        imageUrl: path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: color,
        placeholder: (context, _) => SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, _, _) => _fallbackIcon(),
      );
    }
    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      errorBuilder: (_, _, _) => _fallbackIcon(),
    );
  }

  Widget _fallbackIcon() => Icon(
        Icons.image_not_supported,
        color: Colors.white54,
        size: size,
      );
}
