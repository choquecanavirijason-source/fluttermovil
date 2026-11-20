import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/tryon_catalog.dart';

void main() {
  test(
    'manual categories extend the catalog without changing style geometry',
    () {
      final payload =
          jsonDecode(
                File('test/fixtures/tryon_catalog_v2.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final before = TryOnCatalog.fromJson(payload);
      payload['eye_categories'] = [
        {
          'key': 'eye_hooded',
          'name': 'Encapotado',
          'group': 'lid',
          'detection': 'manual',
          'style_keys': ['cateye'],
        },
      ];
      final after = TryOnCatalog.fromJson(payload);
      expect(after.eyeCategories.single.name, 'Encapotado');
      expect(after.eyeCategories.single.styleKeys, ['cateye']);
      expect(
        after.styles.first.profile?.toJson(),
        before.styles.first.profile?.toJson(),
      );
      payload['eye_categories'][0]['detection'] = 'invented';
      expect(() => TryOnCatalog.fromJson(payload), throwsFormatException);
    },
  );
}
