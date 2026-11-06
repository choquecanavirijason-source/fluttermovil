import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Nominal salon settings; visual scale is calibrated independently of mm.
class CatEyeRecipe {
  static const styleIds = [
    'cateye',
    'wispy',
    'catclassic',
    'foxyeye',
    'natural',
    'dolleye',
    'squirrel',
    'kitten',
    'wetlook',
    'anime',
    'kimk',
  ];
  final int length, technique, thickness, style;
  const CatEyeRecipe({
    this.length = 1,
    this.technique = 0,
    this.thickness = 3,
    this.style = 0,
  });
  String get styleId => styleIds[style];
  String get key =>
      '${styleId}_${style == 0 ? 'v1' : 'v2'}_${length}_${technique}_$thickness';
  Map<String, int> toMap() => {
    'style': style,
    'length': length,
    'technique': technique,
    'thickness': thickness,
  };
  factory CatEyeRecipe.fromMap(Map<String, int> m) => CatEyeRecipe(
    style: m['style'] ?? 0,
    length: m['length']!,
    technique: m['technique']!,
    thickness: m['thickness']!,
  );
  int get roots => (style == 9
      ? [24, 36, 40, 32]
      : style == 8
      ? [36, 48, 40, 48]
      : [72, 48, 40, 56])[technique];
  double get curl =>
      [.58, .65, .55, .38, .48, .72, .62, .54, .52, .64, .61][style];
  double get fan => [9, 15, 9, 7, 10, 13, 10, 8, 8, 15, 12][style].toDouble();
  double get sweep => [20, 6, 12, 32, 3, 0, 10, 14, 8, 2, 12][style].toDouble();
  double lengthAt(double t, int root) {
    final arch = math.pow(math.sin(math.pi * t).clamp(0.0, 1.0), .8);
    return switch (style) {
      1 => (.29 + .24 * arch + .045 * t) * (root % 4 == 2 ? 1.42 : .92),
      2 => .30 + .27 * _smooth(t / .85) - .045 * _smooth((t - .9) / .1),
      3 => .24 + .47 * _smooth(t) - .025 * _smooth((t - .97) / .03),
      4 => .24 + .20 * arch + .025 * t,
      5 => .23 + .43 * math.pow(math.sin(math.pi * t).clamp(0.0, 1.0), .9),
      6 => .24 + .42 * _smooth(t / .72) - .30 * _smooth((t - .72) / .28),
      7 => .23 + .29 * _smooth(t / .80) - .09 * _smooth((t - .88) / .12),
      8 => (.25 + .28 * arch + .035 * t) * (root.isEven ? 1.03 : .93),
      9 => (.21 + .18 * arch) * (root.isEven ? 1.9 : .82),
      10 => (.27 + .23 * arch + .07 * t) * (root % 5 == 2 ? 1.6 : .94),
      _ => .26 + .40 * _smooth(t / .88) - .06 * _smooth((t - .94) / .06),
    };
  }

  int fanSize(int root) => switch (technique) {
    1 => 3,
    2 => 6,
    3 => root.isEven ? 1 : 3,
    _ => 1,
  };
  int get fiberCount => List.generate(roots, fanSize).fold(0, (a, b) => a + b);
}

double _smooth(double t) {
  t = t.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _rootZ(double x) => -.12 - .18 * math.pow(x / 1.5, 2);

/// Crossed tapered ribbons with a common Y=0 attachment row. The renderer's
/// existing root binding supplies the measured lid contour for either camera.
Uint8List buildCatEyeGlb(CatEyeRecipe recipe, {required bool right}) {
  if (recipe.style < 0 ||
      recipe.style >= CatEyeRecipe.styleIds.length ||
      recipe.length < 0 ||
      recipe.length > 2 ||
      recipe.technique < 0 ||
      recipe.technique > 3 ||
      recipe.thickness < 0 ||
      recipe.thickness > 3) {
    throw ArgumentError('Invalid Cat Eye recipe');
  }
  final p = <List<double>>[],
      colors = <List<double>>[],
      uv = <List<double>>[],
      ix = <int>[];
  final rng = math.Random(1101 + recipe.style * 1101);
  final scale = [.78, 1.0, 1.23][recipe.length];
  final diameter = [.05, .07, .10, .15][recipe.thickness];
  void fiber(double t, double length, double angle, double jitter) {
    final x = (.5 - t) * 3, z = _rootZ(x), theta = angle * math.pi / 180;
    final width = .028 * diameter / .15;
    for (final crossed in [false, true]) {
      final start = p.length;
      for (var j = 0; j <= 9; j++) {
        final s = j / 9;
        final cx =
            x +
            math.sin(theta) * length * math.pow(s, 1.12) +
            jitter * length * math.sin(math.pi * s);
        final cy = math.cos(theta) * length * s;
        final cz = z + recipe.curl * length * (1.15 * s * s - .15 * s * s * s);
        final half = width * .5 * (math.pow(1 - s, 1.2) + .025);
        final g = .045 + .12 * math.pow(s, .7);
        for (final side in [-1, 1]) {
          p.add([
            cx + (crossed ? 0 : side * half),
            cy,
            cz + (crossed ? side * half * .65 : 0),
          ]);
          colors.add([g, g, g, 1]);
          uv.add([s, (side + 1) / 2]);
        }
      }
      for (var j = 0; j < 9; j++) {
        final a = start + j * 2;
        ix.addAll([a, a + 1, a + 2, a + 1, a + 3, a + 2]);
      }
    }
  }

  for (var i = 0; i < recipe.roots; i++) {
    final t = i / (recipe.roots - 1);
    final length = recipe.lengthAt(t, i) * scale * (.9 + .2 * rng.nextDouble());
    final angle =
        (.5 - t) * recipe.fan -
        recipe.sweep * _smooth((t - .35) / .65) +
        (rng.nextDouble() - .5) * 6;
    final jitter = (rng.nextDouble() - .5) * .064;
    final count = recipe.fanSize(i);
    for (var f = 0; f < count; f++) {
      final spread = count == 1
          ? 0.0
          : (f / (count - 1) - .5) *
                (recipe.style == 8
                    ? 1.6
                    : recipe.style == 9
                    ? 5
                    : recipe.technique == 2
                    ? 16
                    : 10);
      fiber(t, length * (1 - .06 * spread.abs() / 8), angle + spread, jitter);
    }
  }
  final rail = p.length;
  for (var i = 0; i <= 96; i++) {
    final x = -1.5 + 3 * i / 96;
    for (final y in [0.0, .0045]) {
      p.add([x, y, _rootZ(x)]);
      colors.add([.045, .045, .045, 1]);
      uv.add([i / 96, y / .0045]);
    }
  }
  for (var i = 0; i < 96; i++) {
    final a = rail + i * 2;
    ix.addAll([a, a + 1, a + 2, a + 1, a + 3, a + 2]);
  }
  if (right) {
    for (final v in p) {
      v[0] = -v[0];
    }
    for (var i = 0; i < ix.length; i += 3) {
      final b = ix[i + 1];
      ix[i + 1] = ix[i + 2];
      ix[i + 2] = b;
    }
  }
  final normals = List.generate(p.length, (_) => [0.0, 0.0, 0.0]);
  for (var i = 0; i < ix.length; i += 3) {
    final a = p[ix[i]], b = p[ix[i + 1]], c = p[ix[i + 2]];
    final u = List.generate(3, (k) => b[k] - a[k]),
        v = List.generate(3, (k) => c[k] - a[k]);
    final n = [
      u[1] * v[2] - u[2] * v[1],
      u[2] * v[0] - u[0] * v[2],
      u[0] * v[1] - u[1] * v[0],
    ];
    for (var j = 0; j < 3; j++) {
      for (var k = 0; k < 3; k++) {
        normals[ix[i + j]][k] += n[k];
      }
    }
  }
  for (final n in normals) {
    final mag = math.sqrt(n.fold(0.0, (a, b) => a + b * b));
    if (mag > 0) {
      for (var k = 0; k < 3; k++) {
        n[k] /= mag;
      }
    } else {
      n[2] = 1;
    }
  }
  final bin = BytesBuilder(),
      views = <Map<String, dynamic>>[],
      accessors = <Map<String, dynamic>>[];
  int attribute(List<List<double>> values, String type, {bool bounds = false}) {
    final data = ByteData(values.length * values.first.length * 4);
    var offset = 0;
    for (final row in values) {
      for (final value in row) {
        data.setFloat32(offset, value, Endian.little);
        offset += 4;
      }
    }
    views.add({
      'buffer': 0,
      'byteOffset': bin.length,
      'byteLength': data.lengthInBytes,
      'target': 34962,
    });
    bin.add(data.buffer.asUint8List());
    accessors.add({
      'bufferView': views.length - 1,
      'componentType': 5126,
      'count': values.length,
      'type': type,
      if (bounds)
        'min': List.generate(
          3,
          (k) => values.map((v) => v[k]).reduce(math.min),
        ),
      if (bounds)
        'max': List.generate(
          3,
          (k) => values.map((v) => v[k]).reduce(math.max),
        ),
    });
    return accessors.length - 1;
  }

  final attrs = {
    'POSITION': attribute(p, 'VEC3', bounds: true),
    'NORMAL': attribute(normals, 'VEC3'),
    'COLOR_0': attribute(colors, 'VEC4'),
    'TEXCOORD_0': attribute(uv, 'VEC2'),
  };
  final ids = ByteData(ix.length * 2);
  for (var i = 0; i < ix.length; i++) {
    ids.setUint16(i * 2, ix[i], Endian.little);
  }
  views.add({
    'buffer': 0,
    'byteOffset': bin.length,
    'byteLength': ids.lengthInBytes,
    'target': 34963,
  });
  bin.add(ids.buffer.asUint8List());
  accessors.add({
    'bufferView': views.length - 1,
    'componentType': 5123,
    'count': ix.length,
    'type': 'SCALAR',
  });
  final doc = {
    'asset': {'version': '2.0', 'generator': 'elashes configurable Cat Eye v1'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {'mesh': 0},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': attrs,
            'indices': accessors.length - 1,
            'material': 0,
            'mode': 4,
          },
        ],
      },
    ],
    'materials': [
      {
        'doubleSided': true,
        'pbrMetallicRoughness': {
          'baseColorFactor': [1, 1, 1, 1],
          'metallicFactor': 0,
          'roughnessFactor': .82,
        },
      },
    ],
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': views,
    'accessors': accessors,
    'extras': {
      'recipe': recipe.key,
      'fibers': recipe.fiberCount,
      'rootAxis': 'Y=0',
    },
  };
  final json = utf8.encode(jsonEncode(doc));
  final paddedJson = [...json, ...List.filled((-json.length) % 4, 32)];
  final binary = bin.takeBytes();
  final padding = (-binary.length) % 4;
  final header = ByteData(20)
    ..setUint32(0, 0x46546c67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(
      8,
      28 + paddedJson.length + binary.length + padding,
      Endian.little,
    )
    ..setUint32(12, paddedJson.length, Endian.little)
    ..setUint32(16, 0x4e4f534a, Endian.little);
  final bh = ByteData(8)
    ..setUint32(0, binary.length + padding, Endian.little)
    ..setUint32(4, 0x004e4942, Endian.little);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(paddedJson)
        ..add(bh.buffer.asUint8List())
        ..add(binary)
        ..add(List.filled(padding, 0)))
      .takeBytes();
}
