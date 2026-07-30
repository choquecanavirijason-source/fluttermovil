import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

/// Botón inferior de "analizar mi ojo" (estilo referencia; sin fila
/// Cancelar). El texto ya no es fijo: muestra el nombre del diseño de
/// pestaña seleccionado en el carrusel (antes ese nombre se mostraba debajo
/// de cada miniatura del carrusel — se movió acá).
class EyeTrackingPremiumOjoButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;

  const EyeTrackingPremiumOjoButton({
    super.key,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 64,
      right: 72,
      bottom: 24,
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 37,
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
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.actionGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Positioned(
                  left: 0,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: AppColors.actionGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bookmark, color: Colors.white, size: 24),
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
