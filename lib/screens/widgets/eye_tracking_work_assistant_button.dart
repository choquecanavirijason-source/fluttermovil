import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class EyeTrackingWorkAssistantButton extends StatelessWidget {
  final VoidCallback onTap;

  const EyeTrackingWorkAssistantButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // Centrado en altura con el botón "Natural" (bottom 24, alto 28).
      bottom: 15,
      right: 16,
      child: SafeArea(
        top: false,
        child: Tooltip(
          message: 'Asistente IA: comparar con foto de referencia',
          child: GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(80),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(80),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.smart_toy_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
