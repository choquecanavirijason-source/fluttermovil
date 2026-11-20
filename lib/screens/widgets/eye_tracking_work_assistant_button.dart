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
      // Esquina superior derecha, a la altura del botón de guardar (que
      // queda a su izquierda, ver `EyeTrackingPage`).
      top: 35,
      right: 12,
      // Sin SafeArea: el botón de guardar tampoco la usa, y con ella la
      // barra de estado empujaría el robot más abajo y quedarían desalineados.
      child: Tooltip(
        message: 'Asistente IA: comparar con foto de referencia',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
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
    );
  }
}
