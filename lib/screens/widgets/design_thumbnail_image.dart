import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:Probador/lashes/lash_curl.dart';

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

  /// Prefijo de las curvaturas (`curl:grados,posición,nitidez`): se dibuja la
  /// fibra en vista lateral con el mismo modelo del motor ([LashCurl]).
  static const curlPrefix = 'curl:';

  /// Prefijo de los niveles de intensidad (`fill:0|1|2`): una tira de
  /// pestañas más rala o más tupida.
  static const fillPrefix = 'fill:';

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
    if (path.startsWith(DesignThumbnailImage.fillPrefix)) {
      final level = int.tryParse(
        path.substring(DesignThumbnailImage.fillPrefix.length),
      );
      if (level == null) return _fallbackIcon();
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _FillGlyphPainter(
            level.clamp(0, 2),
            color ?? const Color(0xFF1B1B1B),
          ),
        ),
      );
    }
    if (path.startsWith(DesignThumbnailImage.curlPrefix)) {
      final parts = path
          .substring(DesignThumbnailImage.curlPrefix.length)
          .split(',');
      final values = parts.map(double.tryParse).toList();
      if (values.length != 3 || values.contains(null)) return _fallbackIcon();
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CurlGlyphPainter(
            LashCurl(values[0]!, values[1]!, values[2]!),
            color ?? const Color(0xFF1B1B1B),
          ),
        ),
      );
    }
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
            border: Border.all(
              color: Colors.white.withValues(alpha: .7),
              width: 1.5,
            ),
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

/// Fibra en vista lateral para las miniaturas de curvatura: nace proyectada
/// hacia adelante (como el motor, ~70° desde la vertical) y se dobla hacia
/// arriba según la [LashCurl].
class _CurlGlyphPainter extends CustomPainter {
  _CurlGlyphPainter(this.curl, this.color);
  final LashCurl curl;
  final Color color;

  static const _baseRad = 70 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final profile = curl.profile(10);
    // Puntos en el plano (adelante, arriba) con largo 1.
    final pts = <Offset>[
      for (var i = 0; i < profile.up.length; i++)
        Offset(
          profile.up[i] * math.sin(_baseRad) -
              profile.back[i] * math.cos(_baseRad),
          profile.up[i] * math.cos(_baseRad) +
              profile.back[i] * math.sin(_baseRad),
        ),
    ];
    final minX = pts.map((p) => p.dx).reduce(math.min);
    final maxX = pts.map((p) => p.dx).reduce(math.max);
    final maxY = pts.map((p) => p.dy).reduce(math.max);
    final span = math.max(math.max(maxX - minX, maxY), 1e-6);
    final scale = size.shortestSide * .78 / span;
    final origin = Offset(
      (size.width - (maxX - minX) * scale) / 2 - minX * scale,
      size.height - (size.height - maxY * scale) / 2,
    );
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final p = origin + Offset(pts[i].dx * scale, -pts[i].dy * scale);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.shortestSide * .07)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_CurlGlyphPainter old) =>
      old.curl != curl || old.color != color;
}

/// Tira de pestañas para los niveles de intensidad: más fibras y más
/// marcadas en cada nivel.
class _FillGlyphPainter extends CustomPainter {
  _FillGlyphPainter(this.level, this.color);
  final int level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final count = const [6, 10, 15][level];
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, size.shortestSide * (.035 + .012 * level))
      ..isAntiAlias = true;
    // Línea del párpado (arco suave) y fibras que nacen de ella en abanico.
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final x = w * (.14 + .72 * t);
      final y = h * (.74 - .12 * math.sin(math.pi * t));
      final angle = (t - .5) * 1.1;
      final len = h * (.38 + .14 * math.sin(math.pi * t));
      canvas.drawLine(
        Offset(x, y),
        Offset(x + math.sin(angle) * len, y - math.cos(angle) * len),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FillGlyphPainter old) =>
      old.level != level || old.color != color;
}
