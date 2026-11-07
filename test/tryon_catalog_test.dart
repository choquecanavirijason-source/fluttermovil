import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/cat_eye_recipe.dart';
import 'package:Probador/lashes/lash_render_profile.dart';
import 'package:Probador/lashes/tryon_catalog.dart';

Map<String, dynamic> fixture() => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/tryon_catalog_v1.json').readAsStringSync())
      as Map,
);
List<List<double>> vertices(Uint8List bytes) {
  final h = ByteData.sublistView(bytes), js = h.getUint32(12, Endian.little);
  final doc = jsonDecode(utf8.decode(bytes.sublist(20, 20 + js))) as Map;
  final a = doc['accessors'][0] as Map,
      v = doc['bufferViews'][a['bufferView']] as Map;
  return List.generate(
    a['count'] as int,
    (i) => List.generate(
      3,
      (k) => h.getFloat32(
        28 + js + (v['byteOffset'] as int) + (i * 3 + k) * 4,
        Endian.little,
      ),
    ),
  );
}

class Adapter implements HttpClientAdapter {
  Map<String, dynamic>? response;
  Adapter(this.response);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<dynamic>? cancel,
  ) async {
    if (response == null)
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    expect(options.path, '/catalogs/tryon/manifest');
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual API response loads original styles and an arbitrary new style',
    () {
      final catalog = TryOnCatalog.fromJson(fixture());
      expect(catalog.styles.length, 12);
      for (final s in catalog.styles.where((s) => s.key != 'venus-lift')) {
        expect(s.profile, isNull);
        expect(s.builtinStyle, s.key);
      }
      final custom = catalog.styles.singleWhere((s) => s.key == 'venus-lift');
      expect(custom.builtinStyle, isNull);
      expect(custom.profile, isNotNull);
      final left = vertices(buildCatEyeGlb(custom.recipe(), right: false)),
          right = vertices(buildCatEyeGlb(custom.recipe(), right: true));
      expect(left.length, lessThan(10000));
      for (var i = 0; i < left.length; i++) {
        expect(left[i].every((n) => n.isFinite), isTrue);
        expect(left[i][1], greaterThanOrEqualTo(0));
        expect(right[i][0], -left[i][0]);
      }
      for (final root
          in left
              .sublist(left.length - 194)
              .indexed
              .where((p) => p.$1.isEven)) {
        expect(root.$2[1], 0);
      }
      expect(
        custom.snapshot(applied: custom.recipe())['style_key'],
        'venus-lift',
      );
    },
  );
  test('rename and order change preserve geometry and stable identity', () {
    final json = fixture(), all = json['styles'] as List;
    final before = TryOnCatalog.fromJson(
      json,
    ).styles.singleWhere((s) => s.key == 'venus-lift');
    final changed = all.singleWhere((s) => s['key'] == 'venus-lift') as Map;
    changed['name'] = 'Mirada de moda';
    changed['sort_order'] = 0;
    changed['revision'] = 2;
    final after = TryOnCatalog.fromJson(
      json,
    ).styles.singleWhere((s) => s.key == 'venus-lift');
    expect(after.recipe().key, isNot(before.recipe().key));
    expect(
      vertices(buildCatEyeGlb(before.recipe(), right: false)),
      vertices(buildCatEyeGlb(after.recipe(), right: false)),
    );
  });
  test('incompatible or heavy profiles are rejected', () {
    final json = fixture();
    json['schema_version'] = 2;
    expect(() => TryOnCatalog.fromJson(json), throwsFormatException);
    final profile =
        (fixture()['styles'] as List).singleWhere(
              (s) => s['key'] == 'venus-lift',
            )['profile']
            as Map;
    profile['roots'] = [72, 48, 41, 56];
    expect(
      () => LashRenderProfile.fromJson(Map<String, dynamic>.from(profile)),
      throwsFormatException,
    );
  });
  test('published restrictions must contain their default', () {
    final json = fixture();
    final style = (json['styles'] as List).first as Map;
    style['allowed_lengths'] = [0];
    expect(() => TryOnCatalog.fromJson(json), throwsFormatException);
  });
  test(
    'last valid manifest survives offline and invalid server publications',
    () async {
      final dir = await Directory.systemTemp.createTemp('tryon_contract_');
      addTearDown(() => dir.delete(recursive: true));
      final adapter = Adapter(fixture()),
          dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api'))
            ..httpClientAdapter = adapter;
      final repo = TryOnCatalogRepository(
        dio,
        directoryProvider: () async => dir,
      );
      final first = await repo.load();
      expect(first!.styles.any((s) => s.key == 'venus-lift'), isTrue);
      adapter.response = {'schema_version': 99};
      expect((await repo.load())!.revision, first.revision);
      adapter.response = null;
      expect((await repo.load())!.revision, first.revision);
      await dir.list().forEach((file) => file.deleteSync());
      expect(await repo.load(), isNull);
    },
  );
}
