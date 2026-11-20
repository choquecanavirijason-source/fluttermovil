import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/core/recommendation/eye_shape_analyzer.dart';
import 'package:Probador/core/recommendation/lash_consultation.dart';
import 'package:Probador/lashes/lash_render_profile.dart';
import 'package:Probador/lashes/lash_style_recommender.dart';
import 'package:Probador/lashes/tryon_catalog.dart';

void main() {
  test('professional choices have direct labels and preserve their source', () {
    const consultation = LashConsultation(
      shapeOverride: EyeShape.almendrado,
      eyelid: EyelidType.hooded,
      depth: EyeDepth.deepSet,
      goal: LashGoal.open,
    );
    expect(consultation.title(null), 'Almendrado · Encapotado');
    final saved = consultation.toMap(null);
    expect(saved['shape_source'], 'professional');
    expect(saved['eyelid'], 'hooded');
    expect(saved['depth'], 'deepSet');
    expect(saved['separation_ratio'], isNull);
    expect(
      consultation.notes(null),
      contains('Párpado confirmado por la profesional'),
    );
    expect(const LashConsultation().toMap(null)['shape_source'], isNull);
  });

  test('the selected objective changes the ranking of arbitrary designs', () {
    final payload =
        jsonDecode(
              File('test/fixtures/tryon_catalog_v2.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final source = TryOnCatalog.fromJson(
      payload,
    ).styles.firstWhere((s) => s.profile != null).profile!.toJson();
    TryOnStyle style(String key, List<double> values) => TryOnStyle(
      key: key,
      name: key,
      profile: LashRenderProfile.fromJson({
        ...source,
        'length_profile': [
          {'t': 0, 'length': values[0]},
          {'t': .5, 'length': values[1]},
          {'t': 1, 'length': values[2]},
        ],
      }),
    );
    final styles = [
      style('center', [.2, .9, .2]),
      style('outer', [.2, .35, .9]),
    ];
    const eye = EyeAnalysis(
      shape: EyeShape.almendrado,
      aspectRatio: 3,
      canthalTiltDeg: 0,
      openness: .33,
      asymmetry: 0,
      reliable: true,
    );
    expect(
      LashStyleRecommender.rank(
        styles,
        eye,
        consultation: const LashConsultation(goal: LashGoal.open),
      ).first,
      0,
    );
    expect(
      LashStyleRecommender.rank(
        styles,
        eye,
        consultation: const LashConsultation(goal: LashGoal.elongate),
      ).first,
      1,
    );
  });
}
