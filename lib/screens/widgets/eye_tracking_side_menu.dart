import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

class EyeTrackingSideMenu extends StatelessWidget {
  final VoidCallback onFlashTap;
  final VoidCallback onRotateTap;
  final VoidCallback onDesignTap;
  final VoidCallback onTechniqueTap;
  final VoidCallback onEffectTap;
  final VoidCallback onThicknessTap;

  /// Abre el selector de color. `null` = el estilo solo ofrece negro y el
  /// botón no se muestra.
  final VoidCallback? onColorTap;

  /// Color elegido, para pintar el botón.
  final Color? currentColor;
  final String? activeCategory;

  const EyeTrackingSideMenu({
    super.key,
    required this.onFlashTap,
    required this.onRotateTap,
    required this.onDesignTap,
    required this.onTechniqueTap,
    required this.onEffectTap,
    required this.onThicknessTap,
    this.onColorTap,
    this.currentColor,
    this.activeCategory,
  });

  static const _gap = SizedBox(height: 10);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 10,
      top: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _MenuItem(
            icon: Icons.flash_on_rounded,
            label: 'Flash',
            onTap: onFlashTap,
          ),
          _gap,
          _MenuItem(
            icon: Icons.cameraswitch_rounded,
            label: 'Cámara',
            onTap: onRotateTap,
          ),
          _gap,
          _MenuItem(
            icon: Icons.straighten_rounded,
            label: 'Largo',
            onTap: onDesignTap,
            isActive: activeCategory == 'design',
          ),
          _gap,
          _MenuItem(
            icon: Icons.grain_rounded,
            label: 'Técnica',
            onTap: onTechniqueTap,
            isActive: activeCategory == 'tech',
          ),
          _gap,
          _MenuItem(
            icon: Icons.auto_awesome_rounded,
            label: 'Efecto',
            onTap: onEffectTap,
            isActive: activeCategory == 'effect',
          ),
          _gap,
          _MenuItem(
            icon: Icons.line_weight_rounded,
            label: 'Grosor',
            onTap: onThicknessTap,
            isActive: activeCategory == 'thickness',
          ),
          if (onColorTap != null) ...[
            _gap,
            _ColorMenuItem(
              color: currentColor ?? const Color(0xFF111111),
              onTap: onColorTap!,
              isActive: activeCategory == 'color',
            ),
          ],
        ],
      ),
    );
  }
}

/// Botón del menú lateral para el color de pestaña: misma forma que los
/// demás, con el color elegido pintado en el centro.
class _ColorMenuItem extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  final bool isActive;

  const _ColorMenuItem({
    required this.color,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Color de pestaña',
      child: GestureDetector(
        onTap: onTap,
        child: _Labeled(
          label: 'Color',
          child: Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.actionGreen.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? AppColors.actionGreen : Colors.white24,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: _Labeled(
          label: label,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.actionGreen.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? AppColors.actionGreen : Colors.white24,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo con su nombre debajo, legible sobre la imagen de la cámara.
class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;

  const _Labeled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}
