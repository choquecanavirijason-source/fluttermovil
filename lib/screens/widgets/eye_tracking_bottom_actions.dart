import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

/// Etiqueta inferior de solo lectura que muestra el diseño seleccionado en el
/// carrusel.
class EyeTrackingPremiumOjoButton extends StatelessWidget {
  final String label;

  const EyeTrackingPremiumOjoButton({
    super.key,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 64,
      // Deja libre la columna del botón del robot (right: 16 + ~46 de ancho)
      // con margen, para que no se solapen en pantallas angostas.
      right: 82,
      bottom: 24,
      child: IgnorePointer(
        child: SafeArea(
          top: false,
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            // Stack en vez de Row: con Row, el círculo de la izquierda corre
            // el texto hacia la derecha (el Expanded del texto arranca
            // DESPUÉS del ícono, así que su propio centro no coincide con el
            // centro real del botón). Acá el texto se centra respecto al
            // ancho completo del botón, y el círculo flota aparte, pegado a
            // la izquierda, sin empujarlo.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.actionGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Positioned(
                  left: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: AppColors.actionGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bookmark,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
