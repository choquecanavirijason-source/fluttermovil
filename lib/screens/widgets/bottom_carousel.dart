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
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 15),
        child: Container(
          width: double.infinity,
          // Mismo alto que la versión sin nombre (70): las pestañas
          // Compatible/Explorar están ancladas a una posición fija más
          // arriba (ver EyeTrackingFilterRow, bottom:150) — si este
          // contenedor crece, se les monta encima. Círculo y texto más
          // chicos (44 + texto 9) para que quepan en el mismo espacio.
          height: 70,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: imagePaths.length,
            itemBuilder: (context, index) {
              final isSelected = selectedLash == index;
              final circle = AnimatedScale(
                scale: isSelected ? 1.18 : 0.92,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: labels == null ? 60 : 44,
                  height: labels == null ? 60 : 44,
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
              );
              return GestureDetector(
                onTap: () => onSelect(index),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: labels == null ? 68 : 52,
                  child: labels == null
                      ? Center(child: circle)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            circle,
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
