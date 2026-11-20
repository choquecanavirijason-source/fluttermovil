import 'dart:math' as math;
import '../core/recommendation/eye_shape_analyzer.dart';
import '../core/recommendation/lash_consultation.dart';
import 'tryon_catalog.dart';

/// Initial visual-preference rules, to calibrate with the salon. The ranking
/// depends on geometry, never on a style's name or a fixed list of designs.
class LashStyleRecommender {
  static double score(
    TryOnStyle style,
    EyeAnalysis eye, {
    LashConsultation consultation = const LashConsultation(),
  }) {
    final recipe = style.recipe();
    double average(double start, double end) =>
        List.generate(
          9,
          (i) => recipe.lengthAt(start + (end - start) * i / 8, i),
        ).reduce((a, b) => a + b) /
        9;
    final center = average(.35, .65), outer = average(.75, .95);
    final largest = math.max(center, outer).clamp(.01, double.infinity);
    final emphasis = ((outer - center) / largest).clamp(-1.0, 1.0);
    final sweep = (recipe.sweep / 40).clamp(-1.0, 1.0);
    final curl = (recipe.curl / 1.2).clamp(0.0, 1.0);
    final centered = .5 - .4 * emphasis + .1 * curl;
    final extended = .5 + .4 * emphasis + .1 * sweep;
    final shapePreference = switch (consultation.shapeOverride ?? eye.shape) {
      EyeShape.redondo => .5 + .4 * emphasis + .1 * sweep,
      EyeShape.rasgado => .5 - .4 * emphasis + .1 * curl,
      _ => .6 - .25 * emphasis.abs(),
    };
    final liftPreference = eye.canthalTiltDeg < -4
        ? curl * .8 + (1 - math.max(0, emphasis)) * .2
        : .5;
    final density = (recipe.roots / 120).clamp(0.0, 1.0);
    final separationPreference = !eye.reliable
        ? .5
        : eye.separationRatio < .85
        ? extended
        : eye.separationRatio > 1.15
        ? centered
        : .5;
    final goalPreference = switch (consultation.goal) {
      LashGoal.automatic => shapePreference,
      LashGoal.natural =>
        .5 * (1 - density) + .5 * (1 - (center / 1.2).clamp(0.0, 1.0)),
      LashGoal.open => centered,
      LashGoal.elongate => extended,
      LashGoal.lift => .7 * curl + .3 * (1 - math.max(0, emphasis)),
    };
    final lidPreference =
        consultation.eyelid == EyelidType.hooded ||
            consultation.eyelid == EyelidType.monolid
        ? (centered + curl) / 2
        : .5;
    final depthPreference = switch (consultation.depth) {
      EyeDepth.deepSet => centered,
      EyeDepth.prominent => 1 - density,
      _ => .5,
    };
    return .40 * shapePreference +
        .25 * goalPreference +
        .10 * liftPreference +
        .10 * separationPreference +
        .05 * lidPreference +
        .05 * depthPreference +
        .05 * (1 - density);
  }

  static List<int> rank(
    List<TryOnStyle> styles,
    EyeAnalysis eye, {
    LashConsultation consultation = const LashConsultation(),
  }) {
    final scores = styles
        .map((s) => score(s, eye, consultation: consultation))
        .toList();
    final indices = List.generate(styles.length, (i) => i);
    indices.sort((a, b) {
      final compared = scores[b].compareTo(scores[a]);
      return compared != 0 ? compared : a.compareTo(b);
    });
    return indices;
  }
}
