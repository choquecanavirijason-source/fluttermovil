import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../core/config/env.dart';
import 'cat_eye_recipe.dart';
import 'lash_render_profile.dart';
import 'lash_options.dart';

class TryOnStyle {
  final String key, name, description;
  final String? thumbnail, builtinStyle;
  final LashRenderProfile? profile;
  final int revision, sortOrder;
  final bool active;
  final List<int> lengths, techniques, thicknesses;
  final List<String> eyeTypes;
  final int defaultLength, defaultTechnique, defaultThickness;
  final LashOptionCatalog options;
  const TryOnStyle({
    required this.key,
    required this.name,
    this.description = '',
    this.thumbnail,
    this.builtinStyle,
    this.profile,
    this.options = LashOptionCatalog.bundled,
    this.revision = 0,
    this.sortOrder = 0,
    this.active = true,
    this.lengths = const [0, 1, 2],
    this.techniques = const [0, 1, 2, 3],
    this.thicknesses = const [0, 1, 2, 3],
    this.eyeTypes = const [],
    this.defaultLength = 1,
    this.defaultTechnique = 0,
    this.defaultThickness = 3,
  });
  int get engineStyle {
    final index = CatEyeRecipe.styleIds.indexOf(builtinStyle ?? '');
    return index < 0 ? 0 : index;
  }

  bool get originalCatEye =>
      builtinStyle == 'cateye' &&
      profile == null &&
      defaultLength == 1 &&
      defaultTechnique == 0 &&
      defaultThickness == 3 &&
      options.resolve(1, 0, 3).isOriginalCatEye;
  CatEyeRecipe recipe({int? length, int? technique, int? thickness}) =>
      CatEyeRecipe(
        style: engineStyle,
        options: options.resolve(
          length ?? defaultLength,
          technique ?? defaultTechnique,
          thickness ?? defaultThickness,
        ),
        profile: profile,
        catalogStyleKey: key,
        catalogRevision: revision,
        length: length ?? defaultLength,
        technique: technique ?? defaultTechnique,
        thickness: thickness ?? defaultThickness,
      );
  Map<String, dynamic> snapshot({CatEyeRecipe? applied}) => {
    'style_key': key,
    'style_name': name,
    'revision': applied?.catalogRevision ?? revision,
    'engine_version': 2,
    'resolved_options':
        applied?.options?.toJson() ??
        options
            .resolve(defaultLength, defaultTechnique, defaultThickness)
            .toJson(),
    'builtin_style': builtinStyle,
    'profile': (applied?.profile ?? profile)?.toJson(),
    'render_mode': applied == null ? 'original' : 'procedural',
    'selection': {
      'length': applied?.length ?? defaultLength,
      'technique': applied?.technique ?? defaultTechnique,
      'thickness': applied?.thickness ?? defaultThickness,
    },
  };
  factory TryOnStyle.fromJson(
    Map<String, dynamic> m, {
    LashOptionCatalog options = LashOptionCatalog.bundled,
  }) {
    int integer(Object? n, int min, int max) {
      if (n is! int || n < min || n > max) {
        throw const FormatException('Invalid style option');
      }
      return n;
    }

    List<int> parseOptions(String key, int max) {
      final value = m[key];
      if (value is! List || value.isEmpty || value.length > 64) {
        throw const FormatException('Missing options');
      }
      final result = value.map((v) => integer(v, 0, max)).toList();
      if (result.toSet().length != result.length) {
        throw const FormatException('Duplicate options');
      }
      return List.unmodifiable(result);
    }

    final key = m['key'], name = m['name'], base = m['builtin_style'];
    if (key is! String ||
        !RegExp(r'^[a-z][a-z0-9_-]{1,63}$').hasMatch(key) ||
        name is! String ||
        name.trim().length < 2 ||
        name.length > 120 ||
        ![1, 2].contains(m['engine_version'])) {
      throw const FormatException('Unsupported style');
    }
    if (base != null && !CatEyeRecipe.styleIds.contains(base)) {
      throw const FormatException('Unknown base');
    }
    final profile = m['profile'] == null
        ? null
        : LashRenderProfile.fromJson(
            Map<String, dynamic>.from(m['profile'] as Map),
          );
    if (base == null && profile == null) {
      throw const FormatException('Missing geometry');
    }
    final lengths = parseOptions('allowed_lengths', 4095),
        techniques = parseOptions('allowed_techniques', 4095),
        thicknesses = parseOptions('allowed_thicknesses', 4095);
    final d = Map<String, dynamic>.from(m['defaults'] as Map);
    final l = integer(d['length'], 0, 4095),
        t = integer(d['technique'], 0, 4095),
        th = integer(d['thickness'], 0, 4095);
    if (!lengths.contains(l) ||
        !techniques.contains(t) ||
        !thicknesses.contains(th)) {
      throw const FormatException('Unavailable default');
    }
    for (final id in lengths) {
      options.get('length', id);
    }
    for (final id in techniques) {
      options.get('technique', id);
    }
    for (final id in thicknesses) {
      options.get('thickness', id);
    }
    final eyes = List<String>.from(m['eye_types'] as List);
    if (eyes.any(
      (e) => !const ['ALMOND', 'ROUND', 'UPTURNED', 'DOWNTURNED'].contains(e),
    )) {
      throw const FormatException('Unknown eye shape');
    }
    final thumb = m['thumbnail'] as String?;
    if (thumb != null &&
        !(thumb.startsWith('https://') ||
            thumb.startsWith('http://') ||
            thumb.startsWith('/media/') ||
            thumb.startsWith('data:image/png;base64,'))) {
      throw const FormatException('Invalid image');
    }
    return TryOnStyle(
      key: key,
      options: options,
      name: name.trim(),
      description: m['description'] as String? ?? '',
      thumbnail: Env.mediaUrl(thumb),
      builtinStyle: base as String?,
      profile: profile,
      revision: integer(m['revision'], 1, 2147483647),
      sortOrder: integer(m['sort_order'], 0, 10000),
      active: m['is_active'] as bool,
      lengths: lengths,
      techniques: techniques,
      thicknesses: thicknesses,
      eyeTypes: eyes,
      defaultLength: l,
      defaultTechnique: t,
      defaultThickness: th,
    );
  }
}

class TryOnCatalog {
  final List<TryOnStyle> styles;
  final String revision;
  final LashOptionCatalog options;
  TryOnCatalog(
    this.styles,
    this.revision, [
    this.options = LashOptionCatalog.bundled,
  ]);
  factory TryOnCatalog.fromJson(Map<String, dynamic> m) {
    if (![1, 2].contains(m['schema_version']) ||
        ![1, 2].contains(m['engine_version']) ||
        m['styles'] is! List ||
        (m['styles'] as List).length > 500) {
      throw const FormatException('Unsupported catalog');
    }
    if (m['schema_version'] == 2 && m['options'] is! Map) {
      throw const FormatException('Missing salon options');
    }
    final options = m['schema_version'] == 2
        ? LashOptionCatalog.fromJson(
            Map<String, dynamic>.from(m['options'] as Map),
          )
        : LashOptionCatalog.bundled;
    final all = (m['styles'] as List)
        .map(
          (s) => TryOnStyle.fromJson(
            Map<String, dynamic>.from(s as Map),
            options: options,
          ),
        )
        .toList();
    if (all.map((s) => s.key).toSet().length != all.length ||
        (all.isNotEmpty && !all.any((s) => s.active))) {
      throw const FormatException('Invalid catalog');
    }
    all.sort((a, b) {
      final sort = a.sortOrder.compareTo(b.sortOrder);
      return sort != 0 ? sort : a.key.compareTo(b.key);
    });
    return TryOnCatalog(
      List.unmodifiable(all),
      m['revision'] as String,
      options,
    );
  }
}

/// Fetch once on page entry; a failed/incompatible publication keeps the last
/// valid catalog. Network work never blocks camera startup or frame processing.
class TryOnCatalogRepository {
  final Dio dio;
  final Future<Directory> Function() directoryProvider;
  TryOnCatalogRepository(
    this.dio, {
    Future<Directory> Function()? directoryProvider,
  }) : directoryProvider = directoryProvider ?? getTemporaryDirectory;
  Future<TryOnCatalog?> load() async {
    File? cache;
    try {
      var hostHash = 0x811c9dc5;
      for (final b in utf8.encode(Env.apiBaseUrl)) {
        hostHash = ((hostHash ^ b) * 0x01000193) & 0xffffffff;
      }
      cache = File(
        '${(await directoryProvider()).path}/tryon_manifest_v1_${hostHash.toRadixString(16)}.json',
      );
    } catch (_) {
      /* A missing cache must not prevent a live catalog. */
    }
    final token = CancelToken();
    try {
      final response = await dio
          .get<Map<String, dynamic>>(
            '/catalogs/tryon/manifest',
            cancelToken: token,
          )
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () {
              token.cancel('catalog timeout');
              throw TimeoutException('catalog');
            },
          );
      final json = response.data!;
      final catalog = TryOnCatalog.fromJson(json);
      if (catalog.styles.isEmpty) {
        throw const FormatException('Catalog not initialized');
      }
      if (cache != null) {
        try {
          final temp = File('${cache.path}.tmp');
          await temp.writeAsString(jsonEncode(json), flush: true);
          await temp.rename(cache.path);
        } catch (_) {}
      }
      return catalog;
    } catch (_) {
      try {
        if (cache != null && await cache.exists()) {
          return TryOnCatalog.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(await cache.readAsString()) as Map,
            ),
          );
        }
      } catch (_) {}
      return null;
    }
  }
}
