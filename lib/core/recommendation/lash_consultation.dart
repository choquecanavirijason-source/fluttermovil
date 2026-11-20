import 'eye_shape_analyzer.dart';

enum EyelidType { visibleCrease, hooded, monolid }

enum EyeDepth { balanced, deepSet, prominent }

enum LashGoal { automatic, natural, open, elongate, lift }

extension EyelidTypeLabel on EyelidType {
  String get label => switch (this) {
    EyelidType.visibleCrease => 'Pliegue visible',
    EyelidType.hooded => 'Encapotado',
    EyelidType.monolid => 'Monólido',
  };
}

extension EyeDepthLabel on EyeDepth {
  String get label => switch (this) {
    EyeDepth.balanced => 'Equilibrada',
    EyeDepth.deepSet => 'Hundidos',
    EyeDepth.prominent => 'Prominentes',
  };
}

extension LashGoalLabel on LashGoal {
  String get label => switch (this) {
    LashGoal.automatic => 'Personalizado',
    LashGoal.natural => 'Natural',
    LashGoal.open => 'Abrir la mirada',
    LashGoal.elongate => 'Alargar',
    LashGoal.lift => 'Realzar',
  };
}

/// Session choices confirmed by the professional, kept separate from measured
/// features. Eyelid folds and depth are never inferred from contour aspect.
class LashConsultation {
  final EyeShape? shapeOverride;
  final EyelidType? eyelid;
  final EyeDepth? depth;
  final LashGoal goal;
  const LashConsultation({
    this.shapeOverride,
    this.eyelid,
    this.depth,
    this.goal = LashGoal.automatic,
  });

  String title(EyeAnalysis? analysis) {
    final shape = shapeOverride ?? analysis?.shape;
    if (shape == null) return 'Analizando mirada…';
    return [shape.catalogName, if (eyelid != null) eyelid!.label].join(' · ');
  }

  String notes(EyeAnalysis? analysis) => [
    if (shapeOverride != null || analysis != null) 'Mirada: ${title(analysis)}',
    if (analysis != null) 'Separación: ${analysis.separationLabel}',
    if (analysis != null) 'Inclinación: ${analysis.inclinationLabel}',
    if (analysis != null) 'Equilibrio: ${analysis.symmetryLabel}',
    if (depth != null) 'Profundidad: ${depth!.label}',
    if (shapeOverride != null) 'Forma confirmada por la profesional',
    if (eyelid != null) 'Párpado confirmado por la profesional',
    if (depth != null) 'Profundidad confirmada por la profesional',
    'Objetivo: ${goal.label}',
  ].join(' | ');

  Map<String, dynamic> toMap(EyeAnalysis? analysis) {
    final shape = shapeOverride ?? analysis?.shape;
    final code = switch (shape) {
      EyeShape.redondo => 'ROUND',
      EyeShape.almendrado => 'ALMOND',
      EyeShape.rasgado => 'ELONGATED',
      _ => null,
    };
    return {
      'shape': code,
      'shape_source': code == null
          ? null
          : shapeOverride != null
          ? 'professional'
          : 'automatic',
      'eyelid': eyelid?.name,
      'depth': depth?.name,
      'goal': goal.name,
      'aspect_ratio': analysis?.aspectRatio,
      'separation_ratio': analysis?.separationRatio,
      'inclination_deg': analysis?.canthalTiltDeg,
      'asymmetry': analysis?.asymmetry,
      'left_aspect_ratio': analysis?.leftAspectRatio,
      'right_aspect_ratio': analysis?.rightAspectRatio,
    };
  }
}
