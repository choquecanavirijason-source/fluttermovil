import 'dart:math' as math;

/// Published salon settings. Stable IDs are independent from display order.
class LashOption {
  final int id, revision, order;
  final String name;
  final Map<String, dynamic> parameters;
  const LashOption(
    this.id,
    this.name,
    this.parameters, {
    this.revision = 0,
    this.order = 0,
  });
  factory LashOption.fromJson(Map<String, dynamic> m, String kind) {
    final id = m['id'], name = m['name'], revision = m['revision'];
    if (id is! int ||
        id < 0 ||
        id > 4095 ||
        name is! String ||
        name.trim().length < 2 ||
        name.length > 80 ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Invalid salon option');
    }
    final p = Map<String, dynamic>.from(m['parameters'] as Map);
    double number(String key, double min, double max) {
      final n = p[key];
      if (n is! num || !n.isFinite || n < min || n > max) {
        throw const FormatException('Invalid option parameter');
      }
      return n.toDouble();
    }

    final values = <String, dynamic>{};
    if (kind == 'length') {
      values['scale'] = number('scale', .4, 1.8);
    } else if (kind == 'thickness') {
      values['diameter'] = number('diameter', .03, .25);
    } else if (kind == 'technique') {
      final base = p['base_technique'],
          fibers = p['fibers_per_group'],
          every = p['single_every'] ?? 0;
      if (base is! int ||
          base < 0 ||
          base > 3 ||
          (fibers != null && (fibers is! int || fibers < 1 || fibers > 8)) ||
          every is! int ||
          every < 0 ||
          every > 8) {
        throw const FormatException('Invalid technique');
      }
      values.addAll({
        'base_technique': base,
        'fibers_per_group': fibers,
        'single_every': every,
        'density': p['density'] == null ? 1.0 : number('density', .25, 1.5),
        'spread': p['spread'] == null ? null : number('spread', 0, 24),
      });
    } else {
      throw const FormatException('Unknown option kind');
    }
    return LashOption(
      id,
      name.trim(),
      Map.unmodifiable(values),
      revision: revision,
      order: m['sort_order'] as int? ?? 0,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'revision': math.max(1, revision),
    'sort_order': order,
    'is_active': true,
    'parameters': parameters,
  };
}

class ResolvedLashOptions {
  final LashOption length, technique, thickness;
  const ResolvedLashOptions(this.length, this.technique, this.thickness);
  factory ResolvedLashOptions.fromJson(Map<String, dynamic> m) =>
      ResolvedLashOptions(
        LashOption.fromJson(
          Map<String, dynamic>.from(m['length'] as Map),
          'length',
        ),
        LashOption.fromJson(
          Map<String, dynamic>.from(m['technique'] as Map),
          'technique',
        ),
        LashOption.fromJson(
          Map<String, dynamic>.from(m['thickness'] as Map),
          'thickness',
        ),
      );
  Map<String, dynamic> toJson() => {
    'length': length.toJson(),
    'technique': technique.toJson(),
    'thickness': thickness.toJson(),
  };
  bool get isOriginalCatEye =>
      length.id == 1 &&
      thickness.id == 3 &&
      technique.id == 0 &&
      length.parameters['scale'] == 1 &&
      thickness.parameters['diameter'] == .15 &&
      technique.parameters['base_technique'] == 0 &&
      technique.parameters['fibers_per_group'] == null &&
      (technique.parameters['single_every'] ?? 0) == 0 &&
      technique.parameters['density'] == 1 &&
      technique.parameters['spread'] == null;
}

class LashOptionCatalog {
  final Map<String, List<LashOption>> groups;
  const LashOptionCatalog(this.groups);
  static const bundled = LashOptionCatalog({
    'length': [
      LashOption(0, 'Corto', {'scale': .78}),
      LashOption(1, 'Medio', {'scale': 1.0}),
      LashOption(2, 'Largo', {'scale': 1.23}),
    ],
    'thickness': [
      LashOption(0, '0.05 mm', {'diameter': .05}),
      LashOption(1, '0.07 mm', {'diameter': .07}),
      LashOption(2, '0.10 mm', {'diameter': .10}),
      LashOption(3, '0.15 mm', {'diameter': .15}),
    ],
    'technique': [
      LashOption(0, 'Clásica', {'base_technique': 0, 'density': 1.0}),
      LashOption(1, 'Volumen', {'base_technique': 1, 'density': 1.0}),
      LashOption(2, 'Megavolumen', {'base_technique': 2, 'density': 1.0}),
      LashOption(3, 'Híbrida', {'base_technique': 3, 'density': 1.0}),
    ],
  });
  factory LashOptionCatalog.fromJson(Map<String, dynamic> m) {
    final groups = <String, List<LashOption>>{};
    for (final kind in ['length', 'technique', 'thickness']) {
      final list = m[kind];
      if (list is! List || list.isEmpty || list.length > 64) {
        throw const FormatException('Invalid option catalog');
      }
      final options = list
          .map(
            (e) =>
                LashOption.fromJson(Map<String, dynamic>.from(e as Map), kind),
          )
          .toList();
      if (options.map((e) => e.id).toSet().length != options.length) {
        throw const FormatException('Duplicate option');
      }
      groups[kind] = List.unmodifiable(options);
    }
    return LashOptionCatalog(Map.unmodifiable(groups));
  }
  LashOption get(String kind, int id) => groups[kind]!.firstWhere(
    (o) => o.id == id,
    orElse: () => throw const FormatException('Missing published option'),
  );
  ResolvedLashOptions resolve(int l, int t, int d) => ResolvedLashOptions(
    get('length', l),
    get('technique', t),
    get('thickness', d),
  );
}
