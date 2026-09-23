import 'package:flutter/material.dart';

import 'eye_tracking_back_button.dart';
import 'eye_tracking_header.dart';
import 'eye_tracking_side_menu.dart';
import 'eye_tracking_status_badge.dart';

/// Controles flotantes como **hijos directos** del [Stack] del preview (sin capa full-screen).
class EyeTrackingOverlay {
  EyeTrackingOverlay._();

  static List<Widget> buildSiblings({
    required VoidCallback onBack,
    // `null` oculta el badge por completo: se muestra solo mientras no haya
    // llegado ningún frame de tracking todavía (mensajes de ciclo de vida:
    // permiso de cámara, "iniciando cámara…", error). Una vez que la
    // detección de rostro/ojos está corriendo, la guía de encuadre
    // (`EyePositionGuidePainter`) y el pill de tipo de ojo ya comunican el
    // estado — el badge "Rostro detectado"/"Sin rostro" quedaba redundante
    // y a veces desactualizado.
    String? status,
    String title = 'Almendrado',
    required VoidCallback onSwitchCamera,
    required VoidCallback onFlashTap,
    required VoidCallback onDesignTap,
    required VoidCallback onTechniqueTap,
    required VoidCallback onEffectTap,
    required VoidCallback onThicknessTap,
    required VoidCallback onEyeTypeTap,
    String? activeCategory,
  }) {
    return [
      EyeTrackingBackButton(onTap: onBack),
      EyeTrackingHeader(title: title, onTap: onEyeTypeTap),
      if (status != null)
        Positioned(
          left: 12,
          top: 96,
          child: EyeTrackingStatusBadge(status: status),
        ),
      EyeTrackingSideMenu(
        onFlashTap: onFlashTap,
        onRotateTap: onSwitchCamera,
        onDesignTap: onDesignTap,
        onTechniqueTap: onTechniqueTap,
        onEffectTap: onEffectTap,
        onThicknessTap: onThicknessTap,
        activeCategory: activeCategory,
      ),
    ];
  }
}
