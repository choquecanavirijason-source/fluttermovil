import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/cat_eye_recipe.dart';
import 'package:Probador/lashes/lash_curl.dart';
import 'package:Probador/lashes/lash_options.dart';
import 'package:Probador/lashes/tryon_catalog.dart';
import 'cat_eye_recipe_test.dart' show positions;

Map<String, dynamic> _option(int id, String name, Map<String, dynamic> p) => {
  'id': id,
  'name': name,
  'revision': 1,
  'sort_order': id,
  'is_active': true,
  'parameters': p,
};

Map<String, dynamic> _catalog() => {
  'length': [
    _option(1, 'Medio', {'scale': 1.0}),
  ],
  'technique': [
    _option(0, 'Clásica', {'base_technique': 0}),
  ],
  'thickness': [
    _option(3, '0.15 mm', {'diameter': .15}),
  ],
  'curl': [
    _option(0, 'Recta', {
      'curl_deg': 0,
      'bend_position': .5,
      'bend_sharpness': 0,
    }),
    _option(3, 'Curva C', {
      'curl_deg': 50,
      'bend_position': .5,
      'bend_sharpness': .25,
    }),
  ],
};

Map<String, dynamic> _style({List<int>? curls, int? curl}) => {
  'key': 'prueba',
  'name': 'Prueba',
  'engine_version': 2,
  'builtin_style': 'cateye',
  'revision': 1,
  'sort_order': 0,
  'is_active': true,
  'allowed_lengths': [1],
  'allowed_techniques': [0],
  'allowed_thicknesses': [3],
  'allowed_curls': ?curls,
  'defaults': {'length': 1, 'technique': 0, 'thickness': 3, 'curl': ?curl},
  'eye_types': <String>[],
};

void main() {
  test('una curva recta no se dobla y una C se dobla de forma creciente', () {
    final straight = LashCurl.presets['STRAIGHT']!.profile(10);
    expect(straight.back.every((b) => b.abs() < 1e-9), true);
    expect(straight.up.last, closeTo(1, 1e-6));
    final c = LashCurl.presets['C']!.profile(10);
    for (var i = 1; i < c.back.length; i++) {
      expect(c.back[i], greaterThanOrEqualTo(c.back[i - 1]));
    }
    expect(c.up.last, lessThan(1));
  });

  test('una L dobla cerca de la base con más quiebre que una C', () {
    double bentAtThird(LashCurl curl) => curl.profile(10).back[4];
    expect(
      bentAtThird(LashCurl.presets['L']!),
      greaterThan(bentAtThird(LashCurl.presets['C']!)),
    );
  });

  test('parámetros fuera de rango se rechazan', () {
    for (final p in [
      {'curl_deg': 151, 'bend_position': .5, 'bend_sharpness': 0},
      {'curl_deg': 40, 'bend_position': .95, 'bend_sharpness': 0},
      {'curl_deg': 40, 'bend_position': .5},
    ]) {
      expect(() => LashCurl.fromParameters(p), throwsFormatException);
    }
  });

  test('sin curvaturas el estilo usa su propia curva', () {
    final options = LashOptionCatalog.fromJson(_catalog());
    final style = TryOnStyle.fromJson(_style(), options: options);
    expect(style.curls, isEmpty);
    expect(style.defaultCurl, isNull);
    expect(style.curlOptions, isEmpty);
    expect(style.recipe().curlShape, isNull);
  });

  test('las curvaturas habilitadas cambian la geometría y se guardan', () {
    final options = LashOptionCatalog.fromJson(_catalog());
    expect(options.curls.map((o) => o.name), ['Recta', 'Curva C']);
    final style = TryOnStyle.fromJson(
      _style(curls: [0, 3], curl: 3),
      options: options,
    );
    final initial = style.recipe();
    expect(initial.curlId, 3);
    expect(initial.curlShape, LashCurl.presets['C']);
    final straight = style.recipe(curl: 0);
    expect(straight.key, isNot(initial.key));
    final snapshot = style.snapshot(applied: straight);
    expect((snapshot['selection'] as Map)['curl'], 0);
    expect(
      ((snapshot['resolved_options'] as Map)['curl'] as Map)['name'],
      'Recta',
    );
    final restored = CatEyeRecipe.fromMap(straight.toMap());
    expect(restored.key, straight.key);
    expect(restored.curlId, 0);
  });

  test('una curva inicial que no está habilitada se rechaza', () {
    final options = LashOptionCatalog.fromJson(_catalog());
    expect(
      () => TryOnStyle.fromJson(_style(curls: [0], curl: 3), options: options),
      throwsFormatException,
    );
    expect(
      () => TryOnStyle.fromJson(_style(curl: 3), options: options),
      throwsFormatException,
    );
  });

  test('la separación en altura deja las fibras del grupo en dos niveles', () {
    CatEyeRecipe recipe(double split) => CatEyeRecipe(
      options: ResolvedLashOptions(
        const LashOption(1, 'Medio', {'scale': 1.0}),
        LashOption(9, 'Y', {
          'base_technique': 1,
          'fibers_per_group': 2,
          'single_every': 0,
          'density': 1.0,
          'spread': 0.0,
          'layer_split': split,
        }),
        const LashOption(3, '0.15 mm', {'diameter': .15}),
      ),
    );
    final flat = positions(buildCatEyeGlb(recipe(0), right: false));
    final split = positions(buildCatEyeGlb(recipe(30), right: false));
    final v = CatEyeRecipe.verticesPerFiber;
    // Primer grupo: fibras 0 y 1. Mismo punto de nacimiento.
    expect(split[0][1], closeTo(split[v][1], 1e-9));
    // Sin separación las puntas quedan a la misma altura (salvo variación
    // natural); con 30° una queda claramente más alta que la otra.
    double tipGap(List<List<double>> p) =>
        (p[v ~/ 2 - 1][2] - p[v + v ~/ 2 - 1][2]).abs();
    expect(tipGap(split), greaterThan(tipGap(flat) + .05));
  });
}
