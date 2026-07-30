import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Caché de bytes decodificados por data URI: sin esto, cada rebuild de
/// [BottomCarousel] (ej. cuando `filteredDesignCatalogProvider` reemite al
/// detectar un cambio de forma de ojo) volvía a decodificar el base64 y
/// creaba un `Uint8List` NUEVO con el mismo contenido. `MemoryImage` compara
/// por identidad de la lista de bytes, no por contenido, así que Flutter
/// trataba cada rebuild como una imagen distinta y la repintaba de cero —
/// eso era el parpadeo.
final Map<String, Uint8List> _dataUriCache = {};

/// Decodifica (con caché) un `data:image/...;base64,...` a bytes, o null si
/// [uri] no es una data URI. `NetworkImage`/`Image.network` NO soportan el
/// esquema `data:` en Android/iOS (solo entienden http/https), así que estas
/// imágenes embebidas necesitan `Image.memory` en vez de `Image.network`.
Uint8List? _decodeDataUri(String uri) {
  if (!uri.startsWith('data:')) return null;
  final cached = _dataUriCache[uri];
  if (cached != null) return cached;
  final commaIndex = uri.indexOf(',');
  if (commaIndex == -1) return null;
  try {
    final bytes = base64Decode(uri.substring(commaIndex + 1));
    _dataUriCache[uri] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}

class BottomCarousel extends StatelessWidget {
  final int selectedLash;
  final ValueChanged<int> onSelect;
  /// Cada entrada puede ser un asset local (`assets/...`), una data URI
  /// (`data:image/...;base64,...`) o una URL de red (`http(s)://...`) — el
  /// tipo se infiere del contenido del propio path en [_buildImage], así se
  /// pueden mezclar diseños locales (bundle) y del catálogo remoto en la
  /// misma lista sin coordinar un flag global.
  final List<String> imagePaths;
  /// Nombre a mostrar bajo cada miniatura (ej. "cglamour", "dolleye"), igual
  /// que en el modal de diseños (ver [EyeTrackingLashModal]). Si es null, no
  /// se muestra texto (comportamiento anterior).
  final List<String>? labels;

  const BottomCarousel({
    super.key,
    required this.selectedLash,
    required this.onSelect,
    required this.imagePaths,
    this.labels,
  });

  @override
  Widget build(BuildContext context) {
    // Alto fijo del widget completo (mismo de siempre — ver nota sobre
    // EyeTrackingFilterRow más abajo). El Stack de adentro usa
    // clipBehavior: Clip.none a propósito: el fondo esmerilado (blur) SÍ
    // debe recortarse a la barra redondeada, pero el círculo seleccionado
    // necesita poder "elevarse" (traslación hacia arriba + sombra) por
    // ENCIMA del borde de la barra sin que se corte — por eso el blur y el
    // contenido (ListView) ahora son capas separadas del Stack en vez de
    // que el ClipRRect envuelva todo.
    return SizedBox(
      width: double.infinity,
      // Mismo alto que la versión sin nombre (70): las pestañas
      // Compatible/Explorar están ancladas a una posición fija más arriba
      // (ver EyeTrackingFilterRow, bottom:150) — si este contenedor crece,
      // se les monta encima. Círculo y texto más chicos (44 + texto 9) para
      // que quepan en el mismo espacio.
      height: 70,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 15),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              // Sin este Clip.none, el ListView recorta a su propio alto
              // (70) y el círculo elevado se corta igual que antes, aunque
              // el Stack de más arriba ya no lo esté clipeando.
              clipBehavior: Clip.none,
              itemCount: imagePaths.length,
              itemBuilder: (context, index) {
                final isSelected = selectedLash == index;
                const selectedScale = 1.18;
                final baseSize = labels == null ? 60.0 : 44.0;
                // AnimatedScale agranda el círculo seleccionado solo en el
                // PAINT (Transform.scale), sin agregar espacio de layout —
                // por eso antes se recortaba (el círculo no tenía margen
                // propio reservado arriba para crecer). Envolver en un
                // SizedBox del tamaño MÁXIMO posible (base * selectedScale)
                // reserva ese espacio de verdad en el layout, así el
                // círculo agrandado entra completo sin tocar su tamaño
                // (selectedScale no cambia).
                final circle = SizedBox(
                  width: baseSize * selectedScale,
                  height: baseSize * selectedScale,
                  child: Center(
                    child: AnimatedScale(
                      scale: isSelected ? selectedScale : 0.92,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: baseSize,
                        height: baseSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: isSelected ? 0.95 : 0.45),
                          border: isSelected
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  width: 2,
                                )
                              : null,
                          boxShadow: isSelected
                              ? [
                                  // Sombra "de elevación" (oscura, con
                                  // offset hacia abajo) además del glow
                                  // blanco de siempre — es lo que vende
                                  // visualmente que el círculo está
                                  // flotando por encima del resto, no solo
                                  // más grande.
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.13),
                                    blurRadius: 14,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : [],
                        ),
                        child: ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: _buildImage(imagePaths[index], index),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                // Eleva el círculo seleccionado por encima de la fila
                // (traslación hacia arriba, animada) — junto con la sombra
                // de arriba, da el efecto de "se levanta sobre el layout"
                // en vez de solo agrandarse en el mismo plano.
                final liftedCircle = AnimatedSlide(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  offset: Offset(0, isSelected ? -0.16 : 0),
                  child: circle,
                );
                return GestureDetector(
                  onTap: () => onSelect(index),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: labels == null ? 68 : 52,
                    child: labels == null
                        ? Center(child: liftedCircle)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              liftedCircle,
                              const SizedBox(height: 2),
                              Text(
                                labels![index],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(String path, int index) {
    const errorIcon = Icon(
      Icons.image_not_supported,
      color: Colors.grey,
      size: 32,
    );
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.contain,
        semanticLabel: 'Lash style ${index + 1}',
        errorBuilder: (context, error, stackTrace) => errorIcon,
      );
    }
    final dataBytes = _decodeDataUri(path);
    if (dataBytes != null) {
      return Image.memory(
        dataBytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        semanticLabel: 'Lash style ${index + 1}',
        errorBuilder: (context, error, stackTrace) => errorIcon,
      );
    }
    return Image.network(
      path,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: 'Lash style ${index + 1}',
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
      errorBuilder: (context, error, stackTrace) => errorIcon,
    );
  }
}
