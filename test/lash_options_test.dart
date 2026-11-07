import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/cat_eye_recipe.dart';
import 'package:Probador/lashes/lash_options.dart';
import 'package:Probador/lashes/tryon_catalog.dart';
import 'cat_eye_recipe_test.dart' show positions, parse;

Map<String, dynamic> v2() =>
    jsonDecode(File('test/fixtures/tryon_catalog_v2.json').readAsStringSync())
        as Map<String, dynamic>;
Uint8List geometry(Uint8List bytes) {
  final bin = parse(bytes).bin;
  return Uint8List.view(bin.buffer, bin.offsetInBytes, bin.lengthInBytes);
}

void main() {
  test(
    'v2 API options preserve every original geometry buffer byte for byte',
    () {
      final catalog = TryOnCatalog.fromJson(v2());
      expect(catalog.options.groups['length']!.length, 4);
      for (final style in catalog.styles.where((s) => s.builtinStyle != null)) {
        for (var l = 0; l < 3; l++) {
          for (var t = 0; t < 4; t++) {
            for (var d = 0; d < 4; d++) {
              final original = CatEyeRecipe(
                style: style.engineStyle,
                length: l,
                technique: t,
                thickness: d,
              );
              final configured = style.recipe(
                length: l,
                technique: t,
                thickness: d,
              );
              expect(
                geometry(buildCatEyeGlb(configured, right: false)),
                orderedEquals(geometry(buildCatEyeGlb(original, right: false))),
                reason: '${style.key} $l $t $d',
              );
            }
          }
        }
      }
      expect(
        catalog.styles.singleWhere((s) => s.key == 'cateye').originalCatEye,
        true,
      );
    },
  );
  test(
    'new length technique and thickness generate finite anchored mirrored meshes',
    () {
      final style = TryOnCatalog.fromJson(
        v2(),
      ).styles.singleWhere((s) => s.key == 'custom-5d');
      final recipe = style.recipe();
      expect(recipe.length, 3);
      expect(recipe.technique, 4);
      expect(recipe.thickness, 4);
      expect(recipe.options!.length.name, 'Extra largo');
      expect(recipe.fanSize(0), 5);
      expect(recipe.fiberCount, lessThanOrEqualTo(240));
      final left = positions(buildCatEyeGlb(recipe, right: false)),
          right = positions(buildCatEyeGlb(recipe, right: true));
      expect(left.length, lessThan(10000));
      for (var i = 0; i < left.length; i++) {
        expect(left[i].every((n) => n.isFinite), true);
        expect(right[i][0], -left[i][0]);
      }
      for (var i = 0; i < recipe.fiberCount; i++) {
        expect(left[i * 40][1], 0);
      }
      final restored = CatEyeRecipe.fromMap(
        jsonDecode(jsonEncode(recipe.toMap())) as Map<String, dynamic>,
      );
      expect(restored.key, recipe.key);
      expect(
        buildCatEyeGlb(restored, right: false),
        buildCatEyeGlb(recipe, right: false),
      );
      expect(
        style.snapshot(applied: recipe)['resolved_options'],
        recipe.options!.toJson(),
      );
    },
  );
  test(
    '8D and mixed groups stay bounded while options can change density and diameter',
    () {
      final source = TryOnCatalog.fromJson(
        v2(),
      ).styles.singleWhere((s) => s.key == 'custom-5d').recipe();
      ResolvedLashOptions options(int every) => ResolvedLashOptions(
        source.options!.length,
        LashOption(9, '8D', {
          'base_technique': 2,
          'fibers_per_group': 8,
          'single_every': every,
          'density': 1.5,
          'spread': 20,
        }),
        source.options!.thickness,
      );
      final full = CatEyeRecipe(options: options(0));
      final mixed = CatEyeRecipe(options: options(2));
      expect(full.fanSize(0), 8);
      expect(mixed.fanSize(0), 1);
      expect(mixed.fanSize(1), 8);
      expect(full.fiberCount, lessThanOrEqualTo(240));
      expect(mixed.fiberCount, lessThanOrEqualTo(240));
      expect(
        positions(buildCatEyeGlb(full, right: false)).length,
        lessThan(10000),
      );
    },
  );
  test('option edits invalidate cache and preserve saved snapshots', () {
    final json = v2();
    final before = TryOnCatalog.fromJson(
      json,
    ).styles.singleWhere((s) => s.key == 'custom-5d').recipe();
    final snapshot = before.toMap();
    final option =
        (json['options']['thickness'] as List).singleWhere((e) => e['id'] == 4)
            as Map;
    option['parameters']['diameter'] = .14;
    option['revision'] = 2;
    final after = TryOnCatalog.fromJson(
      json,
    ).styles.singleWhere((s) => s.key == 'custom-5d').recipe();
    expect(before.key, isNot(after.key));
    expect(before.options!.thickness.parameters['diameter'], .12);
    expect(
      CatEyeRecipe.fromMap(snapshot).options!.thickness.parameters['diameter'],
      .12,
    );
  });
  test('missing and invalid dynamic options reject the publication', () {
    final missing = v2();
    (missing['options']['length'] as List).removeWhere((e) => e['id'] == 3);
    expect(() => TryOnCatalog.fromJson(missing), throwsFormatException);
    final invalid = v2();
    (invalid['options']['technique'] as List)
            .last['parameters']['fibers_per_group'] =
        99;
    expect(() => TryOnCatalog.fromJson(invalid), throwsFormatException);
    final future = v2();
    future['schema_version'] = 3;
    expect(() => TryOnCatalog.fromJson(future), throwsFormatException);
  });
}
