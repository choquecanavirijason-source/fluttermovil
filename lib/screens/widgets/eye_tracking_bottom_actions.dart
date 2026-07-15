import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

/// Botón inferior “Ojo de muñeca” (estilo referencia; sin fila Cancelar).
class EyeTrackingPremiumOjoButton extends StatelessWidget {
  final VoidCallback onTap;

  const EyeTrackingPremiumOjoButton({
    super.key,
    required this.onTap,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.actionGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bookmark, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Ojo de muñeca',
                    style: TextStyle(
                      color: AppColors.actionGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
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
