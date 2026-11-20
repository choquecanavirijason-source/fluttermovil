import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/core/recommendation/eye_shape_analyzer.dart';
import 'package:Probador/eye_tracking_model.dart';
import 'package:Probador/lashes/lash_render_profile.dart';
import 'package:Probador/lashes/lash_style_recommender.dart';
import 'package:Probador/lashes/tryon_catalog.dart';

TrackingFrame frame(double aspect, {double tilt = 0, bool face = true}) {
  List<EyePoint> eye(double x, bool right) => [
    EyePoint(x: x - 40, y: 100 + (right ? tilt : -tilt)),
    EyePoint(x: x, y: 100 - 40 / aspect),
    EyePoint(x: x + 40, y: 100 + (right ? -tilt : tilt)),
    EyePoint(x: x, y: 100 + 40 / aspect),
  ];
  return TrackingFrame(
    faceDetected: face,
    leftEye: eye(100, false),
    rightEye: eye(240, true),
    leftIris: null,
    rightIris: null,
    leftOpenRatio: null,
    rightOpenRatio: null,
  );
}

void main() {
  test('independent eye tilt does not change contour aspect or shape', () {
    final original = frame(3.5);
    List<EyePoint> rotateEye(
      List<EyePoint> points,
      double centerX,
      double angle,
    ) => points.map((p) {
      final x = p.x - centerX, y = p.y - 100;
      return EyePoint(
        x: centerX + x * math.cos(angle) - y * math.sin(angle),
        y: 100 + x * math.sin(angle) + y * math.cos(angle),
      );
    }).toList();
    final tilted = TrackingFrame(
      faceDetected: true,
      leftEye: rotateEye(original.leftEye, 100, .3),
      rightEye: rotateEye(original.rightEye, 240, -.3),
      leftIris: null,
      rightIris: null,
      leftOpenRatio: null,
      rightOpenRatio: null,
    );
    final measured = EyeShapeAnalyzer.analyze(tilted);
    expect(measured.aspectRatio, closeTo(3.5, .000001));
    expect(measured.shape, EyeShapeAnalyzer.analyze(original).shape);
  });
  test('shape is independent of tilt and does not infer hooded eyelids', () {
    expect(EyeShapeAnalyzer.analyze(frame(2.3)).shape, EyeShape.redondo);
    expect(EyeShapeAnalyzer.analyze(frame(3)).shape, EyeShape.almendrado);
    expect(EyeShapeAnalyzer.analyze(frame(4.2)).shape, EyeShape.rasgado);
    final down = EyeShapeAnalyzer.analyze(frame(3, tilt: -8));
    expect(down.shape, EyeShape.almendrado);
    expect(down.canthalTiltDeg, lessThan(-4));
  });

  test('separation is normalized to eye width', () {
    final measured = EyeShapeAnalyzer.analyze(frame(3));
    expect(measured.separationRatio, closeTo(.75, .00001));
    expect(measured.separationLabel, 'Cercanos');
    expect(measured.symmetryLabel, 'Apertura equilibrada');
    expect(measured.leftAspectRatio, closeTo(3, .00001));
  });

  test(
    'borderline measurements ask for position instead of committing a label',
    () {
      final session = SessionEyeAnalysis(), start = DateTime(2026);
      for (var i = 0; i <= 30; i++) {
        session.add(frame(2.6), start.add(Duration(milliseconds: i * 100)));
      }
      expect(session.result, isNull);
      expect(session.needsAdjustment, isTrue);
    },
  );

  test('session waits for open samples and locks until explicitly reset', () {
    final session = SessionEyeAnalysis(), start = DateTime(2026);
    for (var i = 0; i < 28; i++) {
      expect(
        session.add(frame(3), start.add(Duration(milliseconds: i * 100))),
        isNull,
      );
    }
    final locked = session.add(
      frame(3),
      start.add(const Duration(milliseconds: 2800)),
    );
    expect(locked?.shape, EyeShape.almendrado);
    expect(
      session.add(frame(4.2), start.add(const Duration(seconds: 4))),
      same(locked),
    );
    session.reset();
    for (var i = 0; i < 40; i++) {
      expect(
        session.add(frame(20), start.add(Duration(milliseconds: i * 100))),
        isNull,
      );
    }
    session.reset();
    for (var i = 0; i <= 30; i++) {
      session.add(frame(4.2), start.add(Duration(milliseconds: i * 100)));
    }
    expect(session.result?.shape, EyeShape.rasgado);
  });

  test('missing face resets the pending collection', () {
    final session = SessionEyeAnalysis(), start = DateTime(2026);
    for (var i = 0; i < 20; i++) {
      session.add(frame(3), start.add(Duration(milliseconds: i * 100)));
    }
    session.add(frame(3, face: false), start.add(const Duration(seconds: 2)));
    expect(
      session.add(frame(3), start.add(const Duration(seconds: 3))),
      isNull,
    );
  });

  test('collection also completes at a low analysis frame rate', () {
    final session = SessionEyeAnalysis(), start = DateTime(2026);
    for (var i = 0; i <= 12; i++) {
      session.add(frame(3), start.add(Duration(milliseconds: i * 250)));
    }
    expect(session.result?.shape, EyeShape.almendrado);
  });

  test('arbitrary new designs are ranked by geometry and not their name', () {
    final payload =
        jsonDecode(
              File('test/fixtures/tryon_catalog_v2.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final catalog = TryOnCatalog.fromJson(payload);
    final source = catalog.styles
        .firstWhere((s) => s.profile != null)
        .profile!
        .toJson();
    TryOnStyle custom(String key, String name, List<double> lengths) =>
        TryOnStyle(
          key: key,
          name: name,
          profile: LashRenderProfile.fromJson({
            ...source,
            'length_profile': [
              {'t': 0, 'length': lengths[0]},
              {'t': .5, 'length': lengths[1]},
              {'t': 1, 'length': lengths[2]},
            ],
          }),
        );
    final outward = custom('new-outward', 'Nombre cualquiera', [.2, .35, .9]);
    final center = custom('new-center', 'Otro nombre', [.2, .9, .2]);
    final round = EyeShapeAnalyzer.analyze(frame(2.3)),
        narrow = EyeShapeAnalyzer.analyze(frame(4.2));
    expect(LashStyleRecommender.rank([center, outward], round).first, 1);
    expect(LashStyleRecommender.rank([center, outward], narrow).first, 0);
    final renamed = custom('renamed', 'Sin relación con Cat Eye', [
      .2,
      .35,
      .9,
    ]);
    expect(
      LashStyleRecommender.score(outward, round),
      LashStyleRecommender.score(renamed, round),
    );
  });
}
