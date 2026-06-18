import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

class PrefsStorage {
  PrefsStorage(this._prefs);

  final SharedPreferences _prefs;

  int? get selectedBranchId => _prefs.getInt(Env.selectedBranchPrefsKey);

  Future<void> setSelectedBranchId(int? id) async {
    if (id == null) {
      await _prefs.remove(Env.selectedBranchPrefsKey);
    } else {
      await _prefs.setInt(Env.selectedBranchPrefsKey, id);
    }
  }

  String? readString(String key) => _prefs.getString(key);

  Future<bool> writeString(String key, String value) =>
      _prefs.setString(key, value);

  Future<bool> remove(String key) => _prefs.remove(key);
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider debe ser sobreescrito en main() con la instancia real.',
  );
});

final prefsStorageProvider = Provider<PrefsStorage>((ref) {
  return PrefsStorage(ref.watch(sharedPreferencesProvider));
});
