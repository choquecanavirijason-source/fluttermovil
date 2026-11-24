import 'dart:convert';

import 'cat_eye_recipe.dart';
import 'lash_options.dart';
import 'tryon_catalog.dart';

/// Mapeo para la técnica (botón robot): largo en mm por zona, del lagrimal
/// al extremo. El cálculo debe coincidir con `lashMap.ts` del admin.
const lashMapPeakMm = 12;
const lashMapMinMm = 7;
const lashMapDefaultZones = 6;

/// Patrones validados con fotos reales del salón, para los estilos base que
/// todavía no tienen mapeo cargado en el admin.
const _validatedMaps = <String, List<int>>{
  'cateye': [9, 10, 11, 12, 13, 14],
  'natural': [9, 10, 11, 12, 11, 10],
};

enum LashMapSource {
  /// Lo definió el salón (admin) o es un patrón validado.
  salon,

  /// Calculado desde la forma del estilo.
  calculated,
}

class ResolvedLashMap {
  const ResolvedLashMap(this.labels, this.source);
  final List<int> labels;
  final LashMapSource source;
}

double _lengthAt(List<({double t, double length})> points, double t) {
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    if (t <= b.t) {
      final span = b.t - a.t;
      return a.length +
          (b.length - a.length) * ((t - a.t) / (span == 0 ? 1 : span));
    }
  }
  return points.last.length;
}

/// Mapeo calculado desde la forma: la zona más larga mide [peakMm] y el
/// resto es proporcional, redondeado a 1 mm y sin bajar de [lashMapMinMm].
///
/// Entre zonas vecinas se cambia a lo sumo 1 mm, como en los mapeos reales
/// del salón (Cat Eye 9→14, Natural 9→12→10): se parte del pico y se
/// avanza hacia cada extremo acotando el salto.
List<int> computeLashMap(
  List<({double t, double length})> points, {
  int zones = lashMapDefaultZones,
  int peakMm = lashMapPeakMm,
}) {
  final min = lashMapMinMm < peakMm ? lashMapMinMm : peakMm;
  final lengths = List.generate(
    zones,
    (i) => _lengthAt(points, zones == 1 ? 0.0 : i / (zones - 1)),
  );
  // Se normaliza con la zona más larga (no con el máximo del perfil, que
  // puede caer entre dos zonas): así esa zona mide exactamente [peakMm].
  final max = lengths.reduce((a, b) => a > b ? a : b);
  final raw = [
    for (final l in lengths) (peakMm * l / max).round().clamp(min, peakMm),
  ];
  var peak = 0;
  for (var i = 1; i < zones; i++) {
    if (raw[i] > raw[peak]) peak = i;
  }
  final map = List<int>.of(raw);
  for (var i = peak - 1; i >= 0; i--) {
    map[i] = raw[i].clamp(map[i + 1] - 1, map[i + 1] + 1).clamp(min, peakMm);
  }
  for (var i = peak + 1; i < zones; i++) {
    map[i] = raw[i].clamp(map[i - 1] - 1, map[i - 1] + 1).clamp(min, peakMm);
  }
  return List.unmodifiable(map);
}

/// mm que desplaza el mapeo un largo: el valor del admin o, si no tiene, el
/// que sale de su escala (Corto 0.78 → −2, Largo 1.23 → +2).
int lashMapOffsetFor(LashOption? length) {
  if (length == null) return 0;
  final explicit = length.parameters['map_offset_mm'];
  if (explicit is int) return explicit;
  final scale = length.parameters['scale'];
  return scale is num ? ((scale - 1) * 10).round() : 0;
}

/// Mapeo para lo que la operaria tiene armado ahora en el probador.
///
/// - Con mapeo del salón y la forma sin cambios: ese mapeo, desplazado
///   según el largo elegido.
/// - Si la forma cambió (diseño guardado con otro perfil) o el estilo no
///   tiene mapeo: calculado desde la forma, con el pico según el largo.
/// - `null` si no hay forma de referencia: el painter usa su patrón fijo.
ResolvedLashMap? resolveLashMap({
  required TryOnStyle? style,
  CatEyeRecipe? applied,
  LashOption? length,
}) {
  if (style == null) return null;
  final offset = lashMapOffsetFor(length);
  final appliedProfile = applied?.profile;
  final shapeChanged =
      appliedProfile != null &&
      (style.profile == null ||
          jsonEncode(appliedProfile.toJson()) !=
              jsonEncode(style.profile!.toJson()));

  final salonMap =
      style.lashMap ??
      (style.profile == null ? _validatedMaps[style.builtinStyle] : null);
  if (salonMap != null && !shapeChanged) {
    return ResolvedLashMap(
      List.unmodifiable(salonMap.map((mm) => (mm + offset).clamp(4, 20))),
      LashMapSource.salon,
    );
  }

  final points = shapeChanged
      ? appliedProfile.points
      : style.profile?.points ?? style.mapProfile;
  if (points == null || points.length < 2) return null;
  return ResolvedLashMap(
    computeLashMap(points, peakMm: (lashMapPeakMm + offset).clamp(4, 20)),
    LashMapSource.calculated,
  );
}
