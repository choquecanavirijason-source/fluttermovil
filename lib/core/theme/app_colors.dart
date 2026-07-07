import 'package:flutter/material.dart';

/// Paleta de marca eLashes — alineada con la app admin.
class AppColors {
  AppColors._();

  // Marca
  static const Color brandPrimary = Color(0xFF094732);
  static const Color brandSidebar = Color(0xFF031910);
  static const Color brandAccent = Color(0xFF10B981);

  // Dark UI
  static const Color darkBg = Color(0xFF0A0A0A);
  static const Color darkCard = Color(0xFF181818);
  static const Color darkCardElevated = Color(0xFF242424);

  // Dorado — nav pill, FAB, acciones primarias
  static const Color goldAccent = Color(0xFFD4A517);

  // Verde de acción — botones del probador/asistente AR (grabar, guardar, robot)
  static const Color actionGreen = Color(0xFF0D5C41);

  static const Color avatarOlive = Color(0xFF7A6520);

  // Online / offline
  static const Color onlineGreen = Color(0xFF22C55E);
  static const Color offlineRed = Color(0xFFEF4444);

  // Estados de ticket / cliente
  static const Color statusReserva = Color(0xFF6366F1);
  static const Color statusEnEspera = Color(0xFFF59E0B);
  static const Color statusEnServicio = Color(0xFF0EA5E9);
  static const Color statusSiendoAtendido = Color(0xFF8B5CF6);
  static const Color statusAtendido = Color(0xFF14B8A6);
  static const Color statusPagado = Color(0xFF22C55E);
  static const Color statusFinalizado = Color(0xFF16A34A);
  static const Color statusCancelado = Color(0xFFEF4444);
  static const Color statusNoSePresento = Color(0xFFDC2626);
  static const Color statusReagendado = Color(0xFF94A3B8);
  static const Color statusSinEstado = Color(0xFF9CA3AF);

  // Texto secundario sobre dark
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textFaint = Color(0xFF9CA3AF);

  // --- Alias de compatibilidad (pantallas previas a la migración) ---
  static const Color brand = brandPrimary;
  static const Color brandDark = brandSidebar;
  static const Color gold = goldAccent;
  static const Color background = darkBg;
  static const Color surface = darkCard;
  static const Color danger = offlineRed;
  static const Color success = onlineGreen;
}
