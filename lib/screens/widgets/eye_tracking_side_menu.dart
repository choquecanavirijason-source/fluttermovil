import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class EyeTrackingSideMenu extends StatelessWidget {
  final VoidCallback onFlashTap;
  final VoidCallback onRotateTap;
  final VoidCallback onDesignTap;
  final VoidCallback onTechniqueTap;
  final VoidCallback onEffectTap;
  final VoidCallback onThicknessTap;

  const EyeTrackingSideMenu({
    super.key,
    required this.onFlashTap,
    required this.onRotateTap,
    required this.onDesignTap,
    required this.onTechniqueTap,
    required this.onEffectTap,
    required this.onThicknessTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 10,
      top: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _MenuItem(asset: 'assets/flash.png', label: '', onTap: onFlashTap),
          const SizedBox(height: 20),
          _MenuItem(asset: 'assets/rotar.png', label: '', onTap: onRotateTap),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/diseño.png',
            label: 'Diseño',
            onTap: onDesignTap,
          ),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/tecnica.png',
            label: 'Técnica',
            onTap: onTechniqueTap,
          ),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/efecto.png',
            label: 'Efecto',
            onTap: onEffectTap,
          ),
          const SizedBox(height: 20),
          _MenuItem(
            asset: 'assets/grosor.png',
            label: 'Grosor',
            onTap: onThicknessTap,
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String asset;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.asset,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            child: label.isNotEmpty
                ? Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.white24),
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
        ],
      ),
    );
  }
}
