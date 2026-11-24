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

  /// Colores de pestaña que ofrece el estilo (ids del catálogo). Los
  /// estilos anteriores al catálogo de colores: solo negro (0).
  final List<int> colors;

  /// Curvaturas que ofrece el estilo. Vacía = usa su propia curva y el
  /// probador no muestra el botón de curvatura.
  final List<int> curls;

  /// Curvatura inicial; `null` = la curva propia del estilo.
  final int? defaultCurl;
  final List<String> eyeTypes;
  final int defaultLength, defaultTechnique, defaultThickness, defaultColor;
  final LashOptionCatalog options;

  /// Mapeo de la técnica definido en el admin (mm por zona, largo Medio).
  final List<int>? lashMap;

  /// Forma de referencia para calcular el mapeo cuando no hay [lashMap]
  /// (el perfil propio o la plantilla del estilo base).
  final List<({double t, double length})>? mapProfile;
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
    this.colors = const [0],
    this.curls = const [],
    this.defaultCurl,
    this.eyeTypes = const [],
    this.defaultLength = 1,
    this.defaultTechnique = 0,
    this.defaultThickness = 3,
    this.defaultColor = 0,
    this.lashMap,
    this.mapProfile,
  });

  /// Opciones de color disponibles en este estilo, en el orden del catálogo.
  List<LashOption> get colorOptions {
    final available = options.colors.where((o) => colors.contains(o.id));
    return available.isEmpty
        ? const [LashOptionCatalog.blackOption]
        : List.unmodifiable(available);
  }

  /// Curvaturas disponibles en este estilo, en el orden del catálogo.
  List<LashOption> get curlOptions =>
      List.unmodifiable(options.curls.where((o) => curls.contains(o.id)));

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

  /// [curl]: id de la curvatura elegida; sin valor, la inicial del estilo
  /// (o su propia curva si no ofrece curvaturas).
  CatEyeRecipe recipe({
    int? length,
    int? technique,
    int? thickness,
    int? curl,
    int fill = 1,
  }) {
    final chosenCurl = curl ?? defaultCurl;
    final shape = chosenCurl == null ? null : options.curlShape(chosenCurl);
    return CatEyeRecipe(
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
      curlShape: shape,
      curlId: shape == null ? null : chosenCurl,
      fillLevel: fill.clamp(0, 2),
    );
  }

  /// [color]: id del color elegido. El negro (0) no se guarda en la receta,
  /// así un servidor todavía sin el catálogo de colores la sigue aceptando.
  Map<String, dynamic> snapshot({
    CatEyeRecipe? applied,
    Map<String, dynamic>? eyeAssessment,
    int? color,
  }) {
    final chosenColor = color ?? defaultColor;
    final base =
        applied?.options?.toJson() ??
        options
            .resolve(defaultLength, defaultTechnique, defaultThickness)
            .toJson();
    // Curvatura: copia de sus parámetros, como el resto de las opciones.
    final curlId = applied == null ? defaultCurl : applied.curlId;
    final curlOption = curlId == null
        ? null
        : options.curls.where((o) => o.id == curlId).firstOrNull;
    final resolved = curlOption == null
        ? base
        : {...base, 'curl': curlOption.toJson()};
    return {
      'eye_assessment': ?eyeAssessment,
      'style_key': key,
      'style_name': name,
      'revision': applied?.catalogRevision ?? revision,
      'engine_version': 2,
      'resolved_options': chosenColor == 0
          ? resolved
          : {...resolved, 'color': options.color(chosenColor).toJson()},
      'builtin_style': builtinStyle,
      'profile': (applied?.profile ?? profile)?.toJson(),
      'render_mode': applied == null ? 'original' : 'procedural',
      'selection': {
        'length': applied?.length ?? defaultLength,
        'technique': applied?.technique ?? defaultTechnique,
        'thickness': applied?.thickness ?? defaultThickness,
        if (chosenColor != 0) 'color': chosenColor,
        if (curlOption != null) 'curl': curlOption.id,
        // Intensidad elegida en el probador (solo si no es la normal).
        if ((applied?.fillLevel ?? 1) != 1) 'fill': applied!.fillLevel,
      },
    };
  }

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
    // Colores: opcionales; los estilos anteriores son solo negro.
    final colors = m['allowed_colors'] == null
        ? const <int>[0]
        : parseOptions('allowed_colors', 4095);
    // Curvaturas: opcionales y pueden venir vacías (curva propia del estilo).
    final curlsRaw = m['allowed_curls'];
    final curls = curlsRaw is List && curlsRaw.isNotEmpty
        ? parseOptions('allowed_curls', 4095)
        : const <int>[];
    final d = Map<String, dynamic>.from(m['defaults'] as Map);
    final curlDefault = d['curl'] == null ? null : integer(d['curl'], 0, 4095);
    if ((curls.isEmpty && curlDefault != null) ||
        (curls.isNotEmpty && !curls.contains(curlDefault))) {
      throw const FormatException('Unavailable default');
    }
    final l = integer(d['length'], 0, 4095),
        t = integer(d['technique'], 0, 4095),
        th = integer(d['thickness'], 0, 4095),
        c = d['color'] == null ? colors.first : integer(d['color'], 0, 4095);
    if (!lengths.contains(l) ||
        !techniques.contains(t) ||
        !thicknesses.contains(th) ||
        !colors.contains(c)) {
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
      (e) => !const [
        'ALMOND',
        'ROUND',
        'ELONGATED',
        'UPTURNED',
        'DOWNTURNED',
      ].contains(e),
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
      colors: colors,
      curls: curls,
      defaultCurl: curlDefault,
      eyeTypes: eyes,
      defaultLength: l,
      defaultTechnique: t,
      defaultThickness: th,
      defaultColor: c,
      lashMap: _parseLashMap(m['lash_map']),
      mapProfile: _parseMapProfile(m['map_profile']),
    );
  }

  /// Datos opcionales del mapeo: si vienen mal se ignoran (la app calcula
  /// o usa el patrón fijo) en vez de descartar el estilo entero.
  static List<int>? _parseLashMap(Object? raw) {
    if (raw is! List || raw.length < 3 || raw.length > 12) return null;
    if (raw.any((v) => v is! int || v < 4 || v > 20)) return null;
    return List.unmodifiable(raw.cast<int>());
  }

  static List<({double t, double length})>? _parseMapProfile(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final points = <({double t, double length})>[];
    for (final p in raw) {
      if (p is! Map) return null;
      final t = p['t'], length = p['length'];
      if (t is! num || length is! num || !t.isFinite || !length.isFinite) {
        return null;
      }
      points.add((t: t.toDouble(), length: length.toDouble()));
    }
    return List.unmodifiable(points);
  }
}

class TryOnEyeCategory {
  final String key, name, group, detection;
  final List<String> styleKeys;
  const TryOnEyeCategory(
    this.key,
    this.name,
    this.group,
    this.detection,
    this.styleKeys,
  );

  factory TryOnEyeCategory.fromJson(Map<String, dynamic> value) {
    final key = value['key'], name = value['name'];
    final group = value['group'], detection = value['detection'];
    final styles = value['style_keys'];
    if (key is! String ||
        key.isEmpty ||
        key.length > 64 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        !const ['shape', 'tilt', 'lid'].contains(group) ||
        !const ['automatic', 'manual'].contains(detection) ||
        styles is! List ||
        styles.length > 500 ||
        styles.any((s) => s is! String)) {
      throw const FormatException('Invalid eye category');
    }
    return TryOnEyeCategory(
      key,
      name,
      group as String,
      detection as String,
      List<String>.unmodifiable(styles),
    );
  }
}

class TryOnCatalog {
  final List<TryOnStyle> styles;
  final String revision;
  final LashOptionCatalog options;
  final List<TryOnEyeCategory> eyeCategories;
  TryOnCatalog(
    this.styles,
    this.revision, [
    this.options = LashOptionCatalog.bundled,
    this.eyeCategories = const [],
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
    final rawEyes = m['eye_categories'] ?? const [];
    if (rawEyes is! List || rawEyes.length > 64) {
      throw const FormatException('Invalid eye categories');
    }
    final eyes = rawEyes
        .map(
          (e) => TryOnEyeCategory.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (eyes.map((e) => e.key).toSet().length != eyes.length) {
      throw const FormatException('Duplicate eye category');
    }
    return TryOnCatalog(
      List.unmodifiable(all),
      m['revision'] as String,
      options,
      List.unmodifiable(eyes),
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
