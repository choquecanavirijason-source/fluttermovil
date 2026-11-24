/// Version 1 of the editable geometry contract shared with the admin/API.
/// Values describe fibers only; camera projection and root binding stay native.
class LashRenderProfile {
  final List<({double t, double length})> points;
  final List<int> roots;
  final double curl,
      fan,
      sweep,
      spikeMultiplier,
      fanSpread,
      megaFanSpread,
      widthMultiplier,
      fill;
  final int spikeEvery, spikeOffset;
  const LashRenderProfile._(
    this.points,
    this.roots,
    this.curl,
    this.fan,
    this.sweep,
    this.spikeEvery,
    this.spikeOffset,
    this.spikeMultiplier,
    this.fanSpread,
    this.megaFanSpread,
    this.widthMultiplier,
    this.fill,
  );

  factory LashRenderProfile.fromJson(Map<String, dynamic> json) {
    double n(Object? value, double min, double max) {
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('Invalid geometry value');
      }
      return value.toDouble();
    }

    int integer(Object? value, int min, int max) {
      if (value is! int || value < min || value > max) {
        throw const FormatException('Invalid geometry count');
      }
      return value;
    }

    final raw = json['length_profile'];
    if (raw is! List || raw.length < 2 || raw.length > 33) {
      throw const FormatException('Invalid length profile');
    }
    final points = raw
        .map((p) {
          final m = Map<String, dynamic>.from(p as Map);
          return (t: n(m['t'], 0, 1), length: n(m['length'], .08, 1.2));
        })
        .toList(growable: false);
    if (points.first.t != 0 || points.last.t != 1) {
      throw const FormatException('Incomplete profile');
    }
    for (var i = 1; i < points.length; i++) {
      if (points[i].t <= points[i - 1].t) {
        throw const FormatException('Unordered profile');
      }
    }
    final rawRoots = json['roots'];
    if (rawRoots is! List || rawRoots.length != 4) {
      throw const FormatException('Invalid roots');
    }
    final roots = rawRoots
        .map((v) => integer(v, 8, 120))
        .toList(growable: false);
    for (var t = 0; t < 4; t++) {
      final count = roots[t];
      final fibers = t == 0
          ? count
          : t == 1
          ? count * 3
          : t == 2
          ? count * 6
          : count ~/ 2 * 4 + count % 2;
      if (fibers > 240) throw const FormatException('Geometry budget exceeded');
    }
    final every = integer(json['spike_every'] ?? 0, 0, 16),
        offset = integer(json['spike_offset'] ?? 0, 0, 15);
    if (every > 0 && offset >= every) {
      throw const FormatException('Invalid spike offset');
    }
    return LashRenderProfile._(
      List.unmodifiable(points),
      List.unmodifiable(roots),
      n(json['curl'], 0, 1.2),
      n(json['fan'], 0, 35),
      n(json['sweep'], -40, 40),
      every,
      offset,
      n(json['spike_multiplier'] ?? 1, .5, 2.5),
      n(json['fan_spread'] ?? 10, 0, 24),
      n(json['mega_fan_spread'] ?? 16, 0, 24),
      n(json['width_multiplier'] ?? 1, .4, 1.8),
      n(json['fill'] ?? 1, .5, 2),
    );
  }
  double lengthAt(double t, int root) {
    var i = 0;
    while (i < points.length - 2 && points[i + 1].t < t) {
      i++;
    }
    final a = points[i], b = points[i + 1];
    final length =
        a.length +
        (b.length - a.length) * ((t - a.t) / (b.t - a.t)).clamp(0.0, 1.0);
    return length *
        (spikeEvery > 0 && root % spikeEvery == spikeOffset
            ? spikeMultiplier
            : 1);
  }

  Map<String, dynamic> toJson() => {
    'length_profile': points
        .map((p) => {'t': p.t, 'length': p.length})
        .toList(),
    'roots': roots,
    'curl': curl,
    'fan': fan,
    'sweep': sweep,
    'spike_every': spikeEvery,
    'spike_offset': spikeOffset,
    'spike_multiplier': spikeMultiplier,
    'fan_spread': fanSpread,
    'mega_fan_spread': megaFanSpread,
    'width_multiplier': widthMultiplier,
    // Solo si cambia: los estilos sin relleno conservan su clave de caché.
    if (fill != 1) 'fill': fill,
  };
}
