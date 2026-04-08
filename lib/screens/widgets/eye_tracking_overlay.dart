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
    required String status,
    String title = 'Almendrado',
    required VoidCallback onSwitchCamera,
    required VoidCallback onFlashTap,
    required VoidCallback onDesignTap,
    required VoidCallback onTechniqueTap,
    required VoidCallback onEffectTap,
    required VoidCallback onThicknessTap,
  }) {
    return [
      EyeTrackingBackButton(onTap: onBack),
      EyeTrackingHeader(title: title),
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
      ),
    ];
  }
}
