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
      // Deja libre la columna del botón del robot (right: 16 + ~46 de ancho).
      right: 82,
      bottom: 22,
      child: IgnorePointer(
        child: SafeArea(
          top: false,
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.only(left: 4, right: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: AppColors.actionGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
