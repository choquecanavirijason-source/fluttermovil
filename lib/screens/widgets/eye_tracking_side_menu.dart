import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:Probador/core/theme/app_colors.dart';

class EyeTrackingSideMenu extends StatelessWidget {
  final VoidCallback onFlashTap;
  final VoidCallback onRotateTap;
  final VoidCallback onDesignTap;
  final VoidCallback onTechniqueTap;
  final VoidCallback onEffectTap;
  final VoidCallback onThicknessTap;
  final String? activeCategory;

  const EyeTrackingSideMenu({
    super.key,
    required this.onFlashTap,
    required this.onRotateTap,
    required this.onDesignTap,
    required this.onTechniqueTap,
    required this.onEffectTap,
    required this.onThicknessTap,
    this.activeCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 10,
      top: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _MenuItem(asset: 'assets/flash.png', onTap: onFlashTap),
          const SizedBox(height: 20),
          _MenuItem(asset: 'assets/rotar.png', onTap: onRotateTap),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/diseño.png',
            onTap: onDesignTap,
            isActive: activeCategory == 'design',
          ),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/tecnica.png',
            onTap: onTechniqueTap,
            isActive: activeCategory == 'tech',
          ),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/efecto.png',
            onTap: onEffectTap,
            isActive: activeCategory == 'effect',
          ),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/grosor.png',
            onTap: onThicknessTap,
            isActive: activeCategory == 'thickness',
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String asset;
  final VoidCallback onTap;
  final bool isActive;

  const _MenuItem({
    required this.asset,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.actionGreen.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: isActive
                    ? AppColors.actionGreen
                    : Colors.white24,
              ),
            ),
            child: Image.asset(
              asset,
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.circle_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
