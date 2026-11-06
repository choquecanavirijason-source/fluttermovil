import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/cat_eye_recipe.dart';

({Map<String, dynamic> doc, ByteData bin}) parse(Uint8List bytes) {
  final header = ByteData.sublistView(bytes);
  expect(header.getUint32(0, Endian.little), 0x46546c67);
  expect(header.getUint32(8, Endian.little), bytes.length);
  final size = header.getUint32(12, Endian.little);
  return (
    doc:
        jsonDecode(utf8.decode(bytes.sublist(20, 20 + size)))
            as Map<String, dynamic>,
    bin: ByteData.sublistView(bytes, 28 + size),
  );
}

List<List<double>> positions(Uint8List bytes) {
  final data = parse(bytes);
  final a = data.doc['accessors'][0];
  final view = data.doc['bufferViews'][a['bufferView']];
  return List.generate(
    a['count'],
    (i) => List.generate(
      3,
      (k) => data.bin.getFloat32(
        view['byteOffset'] + (i * 3 + k) * 4,
        Endian.little,
      ),
    ),
  );
}

void main() {
  test(
    'all 528 recipes are bounded, finite, mirrored and retain the root rail',
    () {
      final keys = <String>{};
      for (var style = 0; style < CatEyeRecipe.styleIds.length; style++) {
        for (var l = 0; l < 3; l++) {
          for (var t = 0; t < 4; t++) {
            for (var d = 0; d < 4; d++) {
              final recipe = CatEyeRecipe(
                style: style,
                length: l,
                technique: t,
                thickness: d,
              );
              keys.add(recipe.key);
              final bytes = buildCatEyeGlb(recipe, right: false),
                  right = buildCatEyeGlb(recipe, right: true);
              final data = parse(bytes);
              final p = positions(bytes), r = positions(right);
              expect(p.length, recipe.fiberCount * 40 + 194);
              expect(p.length, lessThan(10000));
              expect(data.doc['materials'][0]['doubleSided'], true);
              for (var i = 0; i < p.length; i++) {
                expect(p[i].every((v) => v.isFinite), true);
                expect(r[i][0], -p[i][0]);
                expect(r[i][1], p[i][1]);
                expect(r[i][2], p[i][2]);
                expect(p[i][1], greaterThanOrEqualTo(0));
              }
              final rail = p.sublist(p.length - 194);
              expect(rail.first[0], -1.5);
              expect(rail[192][0], 1.5);
              for (var i = 0; i < 194; i += 2) {
                expect(rail[i][1], 0);
              }
              final indexAccessor = data.doc['accessors'].last;
              final view = data.doc['bufferViews'][indexAccessor['bufferView']];
              for (var i = 0; i < indexAccessor['count']; i++) {
                expect(
                  data.bin.getUint16(view['byteOffset'] + i * 2, Endian.little),
                  lessThan(p.length),
                );
              }
            }
          }
        }
      }
      expect(keys.length, 528);
    },
  );
  test(
    'length changes fibers without moving the attachment; thickness changes width',
    () {
      final short = positions(
        buildCatEyeGlb(const CatEyeRecipe(length: 0), right: false),
      );
      final long = positions(
        buildCatEyeGlb(const CatEyeRecipe(length: 2), right: false),
      );
      expect(long[18][1] / short[18][1], closeTo(1.23 / .78, 1e-6));
      final thin = positions(
        buildCatEyeGlb(const CatEyeRecipe(thickness: 0), right: false),
      );
      final thick = positions(
        buildCatEyeGlb(const CatEyeRecipe(thickness: 3), right: false),
      );
      expect(
        (thick[1][0] - thick[0][0]) / (thin[1][0] - thin[0][0]),
        closeTo(3, 1e-4),
      );
      expect(
        short.sublist(short.length - 194),
        long.sublist(long.length - 194),
      );
    },
  );
  test('techniques have individual, fan, mega fan and mixed fiber counts', () {
    expect(List.generate(4, (t) => CatEyeRecipe(technique: t).fiberCount), [
      72,
      144,
      240,
      112,
    ]);
    expect(
      () => buildCatEyeGlb(const CatEyeRecipe(length: 4), right: false),
      throwsArgumentError,
    );
  });
}
