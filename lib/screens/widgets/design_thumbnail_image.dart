import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

/// Miniatura de una opción del menú de personalización (diseño/técnica/
/// efecto/grosor).
///
/// Usa [CachedNetworkImage] cuando [path] es una URL remota — los diseños
/// reales del catálogo (panel admin) traen su imagen como URL — o
/// [Image.asset] cuando es un asset local empaquetado, como siguen siendo
/// hoy las categorías que el backend todavía no expone (tech/effect/
/// thickness, ver `LashCustomizationCatalog`).
class DesignThumbnailImage extends StatefulWidget {
  const DesignThumbnailImage({
    super.key,
    required this.path,
    required this.size,
    this.color,
  });

  final String path;
  final double size;
  final Color? color;

  @override
  State<DesignThumbnailImage> createState() => _DesignThumbnailImageState();
}

class _DesignThumbnailImageState extends State<DesignThumbnailImage> {
  MemoryImage? _embeddedImage;
  String get path => widget.path;
  double get size => widget.size;
  Color? get color => widget.color;

  @override
  void initState() {
    super.initState();
    _decodeEmbeddedImage();
  }

  @override
  void didUpdateWidget(covariant DesignThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != path) _decodeEmbeddedImage();
  }

  void _decodeEmbeddedImage() {
    _embeddedImage = null;
    if (!path.startsWith('data:image/')) return;
    try {
      _embeddedImage = MemoryImage(
        base64Decode(path.substring(path.indexOf(',') + 1)),
      );
    } catch (_) {
      // Invalid embedded images use the same fallback as failed downloads.
    }
  }

  bool get _isNetwork =>
      path.startsWith('http://') || path.startsWith('https://');

  /// Prefijo de las muestras del catálogo de colores (`swatch:#RRGGBB`).
  static const swatchPrefix = 'swatch:';

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return _fallbackIcon();
    if (path.startsWith(swatchPrefix)) return _swatch();
    if (path.startsWith('data:image/')) {
      final image = _embeddedImage;
      if (image == null) return _fallbackIcon();
      return Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: color,
        errorBuilder: (_, _, _) => _fallbackIcon(),
      );
    }
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

  /// Muestra circular del color de pestaña, con un brillo suave para que
  /// los tonos oscuros (negro, café) se distingan sobre el panel de cristal.
  Widget _swatch() {
    final hex = path.substring(swatchPrefix.length).replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16);
    if (hex.length != 6 || value == null) return _fallbackIcon();
    final base = Color(0xFF000000 | value);
    final diameter = size * .78;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-.35, -.4),
              radius: .95,
              colors: [Color.lerp(base, Colors.white, .28)!, base],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .25),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon() =>
      Icon(Icons.image_not_supported, color: Colors.white54, size: size);
}
