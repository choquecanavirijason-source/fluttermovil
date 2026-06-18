import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';

class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  static FlutterSecureStorage defaultInstance() => const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );

  Future<String?> readToken() => _storage.read(key: Env.tokenStorageKey);

  Future<bool> hasToken() async {
    final value = await readToken();
    return value != null && value.isNotEmpty;
  }

  Future<void> writeToken(String token) =>
      _storage.write(key: Env.tokenStorageKey, value: token);

  Future<void> clearToken() => _storage.delete(key: Env.tokenStorageKey);

  Future<void> clearAll() => _storage.deleteAll();
}

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage(SecureStorage.defaultInstance());
});
