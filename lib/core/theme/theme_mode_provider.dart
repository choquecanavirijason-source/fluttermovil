import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs_storage.dart';

/// Controla el modo de tema (sistema / claro / oscuro) y lo persiste en prefs.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final raw = ref.read(prefsStorageProvider).readString(_key);
    return _parse(raw);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(prefsStorageProvider).writeString(_key, mode.name);
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'system':
        return ThemeMode.system;
      case 'dark':
        return ThemeMode.dark;
      default:
        // Claro por defecto (look de los mockups del cliente).
        return ThemeMode.light;
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
