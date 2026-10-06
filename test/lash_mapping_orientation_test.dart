import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/core/recommendation/eye_shape_analyzer.dart';
import 'package:Probador/eye_tracking_alignment.dart';
import 'package:Probador/eye_tracking_mapping_painter.dart';
import 'package:Probador/eye_tracking_model.dart';
import 'package:Probador/eye_tracking_photo_pipeline.dart';

/// Rostro sintético DERECHO en una imagen de 1000×1000, con los ojos en el
/// orden de MediaPipe: `leftEye` = el de la izquierda de la imagen (índices
/// 33/133…), `rightEye` = el de la derecha (362/263…). Las comisuras
/// externas quedan un poco más altas (mirada levemente elevada).
TrackingFrame uprightFace() {
  EyePoint p(double x, double y) => EyePoint(x: x, y: y);

  // Párpado superior en orden mezclado a propósito: el painter lo ordena.
  List<EyePoint> lid(double inner, double outer) {
    final pts = <EyePoint>[];
    for (final t in [0.0, 0.5, 0.25, 1.0, 0.75, 0.125, 0.875, 0.625]) {
      final x = inner + (outer - inner) * t;
      final y = 500 - 16 * math.sin(math.pi * t) - 5 * t;
      pts.add(p(x, y));
    }
    return pts;
  }

  final contour = [
    for (int i = 0; i < 36; i++)
      p(
        500 + 200 * math.cos(-math.pi / 2 + i * 2 * math.pi / 36),
        550 + 250 * math.sin(-math.pi / 2 + i * 2 * math.pi / 36),
      ),
  ];

  return TrackingFrame(
    faceDetected: true,
    imageWidth: 1000,
    imageHeight: 1000,
    faceContour: contour,
    // [33 externa, 133 interna, superiores…, inferiores…]
    leftEye: [
      p(360, 495),
      p(440, 500),
      p(380, 487),
      p(400, 484),
      p(420, 487),
      p(380, 509),
      p(400, 512),
      p(420, 509),
    ],
    // [362 interna, 263 externa, superiores…, inferiores…]
    rightEye: [
      p(560, 500),
      p(640, 495),
      p(620, 487),
      p(600, 484),
      p(580, 487),
      p(620, 509),
      p(600, 512),
      p(580, 509),
    ],
    leftIris: p(400, 498),
    rightIris: p(600, 498),
    leftOpenRatio: 0.3,
    rightOpenRatio: 0.3,
    leftUpperLid: lid(440, 360),
    rightUpperLid: lid(560, 640),
  );
}

/// Transforma TODOS los landmarks con [f], dejando la identidad de cada ojo
/// igual (como hace MediaPipe al ver la cara girada).
TrackingFrame mapFrame(
  TrackingFrame frame,
  Offset Function(Offset) f, {
  bool dropContour = false,
}) {
  EyePoint m(EyePoint p) {
    final o = f(Offset(p.x, p.y));
    return EyePoint(x: o.dx, y: o.dy);
  }

  List<EyePoint> all(List<EyePoint> pts) => pts.map(m).toList();
  return TrackingFrame(
    faceDetected: true,
    imageWidth: frame.imageWidth,
    imageHeight: frame.imageHeight,
    faceContour: dropContour ? const [] : all(frame.faceContour),
    leftEye: all(frame.leftEye),
    rightEye: all(frame.rightEye),
    leftIris: m(frame.leftIris!),
    rightIris: m(frame.rightIris!),
    leftOpenRatio: frame.leftOpenRatio,
    rightOpenRatio: frame.rightOpenRatio,
    leftUpperLid: all(frame.leftUpperLid),
    rightUpperLid: all(frame.rightUpperLid),
  );
}

Offset Function(Offset) rotation(double degrees) {
  final a = degrees * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  return (o) {
    final dx = o.dx - 500, dy = o.dy - 500;
    return Offset(500 + dx * c - dy * s, 500 + dx * s + dy * c);
  };
}

void expectOffsetsClose(List<Offset> actual, List<Offset> expected) {
  expect(actual.length, expected.length);
  for (int i = 0; i < actual.length; i++) {
    expect(
      (actual[i] - expected[i]).distance,
      lessThan(1e-6),
      reason: 'punto $i: $actual vs $expected',
    );
  }
}

double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

void main() {
  group('LashMappingPainter.layoutFor', () {
    final upright = uprightFace();
    final base = LashMappingPainter.layoutFor(upright, styleId: 'cateye');

    test('rostro vertical: 9→14 de interna a externa, hacia la mejilla', () {
      expect(base, hasLength(2));
      final left = base[0], right = base[1];
      expect(left.labels, [9, 10, 11, 12, 13, 14]);
      // Ojo izquierdo de la imagen: la interna está a la DERECHA (x mayor).
      expect(left.bases.first.dx, greaterThan(left.bases.last.dx));
      // Ojo derecho de la imagen: la interna está a la IZQUIERDA.
      expect(right.bases.first.dx, lessThan(right.bases.last.dx));
      for (final l in base) {
        for (int i = 0; i < l.bases.length; i++) {
          // Mapeo hacia la mejilla = hacia abajo con la cara derecha.
          expect(l.tips[i].dy, greaterThan(l.bases[i].dy));
        }
        expect(l.labelAngle.abs(), lessThan(0.05));
      }
    });

    for (final degrees in [90.0, -90.0, 180.0, 37.0]) {
      test('rostro rotado ${degrees.toInt()}°: mismo mapeo, girado', () {
        final r = rotation(degrees);
        final rotated = LashMappingPainter.layoutFor(
          mapFrame(upright, r),
          styleId: 'cateye',
        );
        expect(rotated, hasLength(2));
        for (int e = 0; e < 2; e++) {
          expect(rotated[e].labels, base[e].labels);
          expectOffsetsClose(rotated[e].bases, base[e].bases.map(r).toList());
          expectOffsetsClose(rotated[e].tips, base[e].tips.map(r).toList());
          expectOffsetsClose(
            rotated[e].labelCenters,
            base[e].labelCenters.map(r).toList(),
          );
          // Números nunca cabeza abajo en pantalla.
          expect(rotated[e].labelAngle.abs(), lessThanOrEqualTo(math.pi / 2));
        }
        if (degrees == 180) {
          expect(rotated[0].labelAngle.abs(), lessThan(0.05));
        }
        if (degrees.abs() == 90) {
          expect(rotated[0].labelAngle.abs(), closeTo(math.pi / 2, 0.05));
        }
      });
    }

    test('rostro corrido a un lado: no se invierten las comisuras', () {
      // Antes la interna se buscaba contra el centro de la IMAGEN: con la
      // cara corrida, en el ojo derecho quedaban intercambiadas.
      Offset shift(Offset o) => o.translate(-300, 0);
      final moved = LashMappingPainter.layoutFor(
        mapFrame(upright, shift),
        styleId: 'cateye',
      );
      for (int e = 0; e < 2; e++) {
        expectOffsetsClose(moved[e].bases, base[e].bases.map(shift).toList());
      }
    });

    test(
      'captura en modo invertido: la grilla va a la mejilla, no a la ceja',
      () {
        // La cámara ve la cara cabeza abajo; el asistente gira foto y
        // landmarks 180° al recortar la banda. Sin ninguna corrección extra
        // (el viejo `towardForehead`), las líneas tienen que ir hacia el mentón.
        final asSeen = mapFrame(upright, rotation(180));
        final band = EyeTrackingPhotoPipeline.frameForCapturedBand(
          asSeen,
          const Size(1000, 1000),
          rotate180: true,
        )!;
        final c = band.faceContour;
        final towardChin = Offset(c[18].x - c[0].x, c[18].y - c[0].y);
        final layouts = LashMappingPainter.layoutFor(band, styleId: 'cateye');
        expect(layouts, hasLength(2));
        for (final l in layouts) {
          expect(l.labels.first, 9);
          for (int i = 0; i < l.bases.length; i++) {
            expect(dot(l.tips[i] - l.bases[i], towardChin), greaterThan(0));
          }
        }
      },
    );

    test('sin contorno facial, rostro a 180°: igual va hacia la mejilla', () {
      final r = rotation(180);
      final noContour = LashMappingPainter.layoutFor(
        mapFrame(upright, r, dropContour: true),
        styleId: 'cateye',
      );
      // Con la cara invertida el mentón queda ARRIBA en la imagen.
      for (final l in noContour) {
        for (int i = 0; i < l.bases.length; i++) {
          expect(
            dot(l.tips[i] - l.bases[i], const Offset(0, -1)),
            greaterThan(0),
          );
        }
      }
    });
  });

  group('Invertir en el probador', () {
    test('la guía de encuadre evalúa el rostro donde se lo ve', () {
      // Clienta cabeza abajo en el preview; con "Invertir" la vista gira 180°
      // y la operaria la ve derecha. Girar el frame antes de evaluar tiene
      // que dar lo mismo que un rostro derecho.
      const screen = Size(1000, 1000);
      final upright = uprightFace();
      final seenInverted = mapFrame(upright, rotation(180));
      final evaluated = EyeAlignmentGuide.evaluate(
        EyeTrackingPhotoPipeline.rotateFrame180(seenInverted)!,
        screen,
      );
      final reference = EyeAlignmentGuide.evaluate(upright, screen);
      expect(evaluated.faceFramed, reference.faceFramed);
      expect(evaluated.eyesClosed, reference.eyesClosed);
    });
  });

  group('Línea de ojos de la guía', () {
    const screen = Size(1000, 1000);
    // Con canvas = imagen (escala 1), la línea queda en
    // 160 + 0.44·560 ≈ 406; el rostro sintético tiene los ojos en y≈498.
    final lineY = EyeAlignmentGuide.eyeLineY(screen);
    Offset Function(Offset) eyesTo(double y) =>
        (o) => o.translate(0, y - 498);

    test('se pinta verde sólo con los ojos sobre la línea', () {
      final onLine = mapFrame(uprightFace(), eyesTo(lineY));
      expect(EyeAlignmentGuide.isEyesOnLine(onLine, screen), isTrue);
      final low = mapFrame(uprightFace(), eyesTo(lineY + 80));
      expect(EyeAlignmentGuide.isEyesOnLine(low, screen), isFalse);
      // Es requisito para capturar: con los ojos fuera de la línea nunca
      // queda "listo", aunque el resto se cumpla.
      expect(EyeAlignmentGuide.evaluate(low, screen).ready, isFalse);
      final status = EyeAlignmentGuide.evaluate(onLine, screen);
      expect(
        status.ready,
        status.faceFramed && status.eyesClosed && status.eyesOnLine,
      );
    });

    test('clienta echada: la línea girada cae sobre los ojos reales', () {
      // Cara cabeza abajo con los ojos donde queda la línea de la guía
      // GIRADA (reflejada respecto del centro): 1000 − 406.
      final seen = mapFrame(
        mapFrame(uprightFace(), eyesTo(lineY)),
        rotation(180),
      );
      expect(seen.leftIris!.y, closeTo(1000 - lineY, 1));
      expect(
        EyeAlignmentGuide.isEyesOnLine(
          EyeTrackingPhotoPipeline.rotateFrame180(seen)!,
          screen,
        ),
        isTrue,
      );
    });

    test('franja de recorte reflejada con la clienta echada', () {
      // Ojos a ~60 % del alto (guía girada): con la franja normal
      // (22 %–64 %) quedan pegados al borde; reflejada (36 %–78 %), adentro.
      final seen = mapFrame(
        mapFrame(uprightFace(), eyesTo(lineY)),
        rotation(180),
      );
      double eyeFraction(bool flip) {
        final band = EyeTrackingPhotoPipeline.frameForCapturedBand(
          seen,
          const Size(1000, 1000),
          flipEyeBand: flip,
        )!;
        return band.leftIris!.y / band.imageHeight;
      }

      expect(eyeFraction(false), greaterThan(0.85));
      expect(eyeFraction(true), inInclusiveRange(0.35, 0.65));
    });
  });

  group('Controles de ajuste manual del asistente', () {
    test('cada panel mueve la grilla que se ve de su lado', () {
      final upright = uprightFace();
      final inverted = mapFrame(upright, rotation(180));
      expect(LashMappingPainter.leftEyeIsOnScreenLeft(upright), isTrue);
      // Clienta echada: el `leftEye` de MediaPipe queda a la derecha.
      expect(LashMappingPainter.leftEyeIsOnScreenLeft(inverted), isFalse);

      // El panel izquierdo con la cara invertida controla `rightEye`, y
      // moverlo tiene que mover la grilla que está a la IZQUIERDA.
      final before = LashMappingPainter.layoutFor(inverted, styleId: 'cateye');
      final after = LashMappingPainter.layoutFor(
        inverted,
        styleId: 'cateye',
        rightEyeOffset: const Offset(10, 0),
      );
      double minX(EyeMappingLayout l) =>
          l.bases.map((p) => p.dx).reduce(math.min);
      final leftGridIndex = minX(before[0]) < minX(before[1]) ? 0 : 1;
      expect(
        minX(after[leftGridIndex]) - minX(before[leftGridIndex]),
        closeTo(10, 1e-6),
      );
    });

    test('la franja de la grilla en pantalla sigue a los ojos', () {
      const panel = Size(1000, 1000);
      final f = uprightFace();
      final extent = LashMappingPainter.verticalExtentOnCanvas(
        f,
        panel,
        styleId: 'cateye',
      )!;
      // Ojos en y≈498; la grilla va hacia la mejilla (abajo).
      expect(extent.top, lessThan(498));
      expect(extent.bottom, greaterThan(498));
      final moved = LashMappingPainter.verticalExtentOnCanvas(
        f,
        panel,
        styleId: 'cateye',
        leftEyeOffset: const Offset(0, 50),
        rightEyeOffset: const Offset(0, 50),
      )!;
      expect(moved.top, closeTo(extent.top + 50, 1e-6));
    });

    test('al girar foto y grilla, el ajuste ya hecho gira con ellas', () {
      final f = uprightFace();
      const offset = Offset(7, -4);
      final base = LashMappingPainter.layoutFor(
        f,
        styleId: 'cateye',
        leftEyeOffset: offset,
      );
      // Lo que hace `_toggleReferenceRotation`: gira el frame y niega el
      // ajuste. La grilla resultante tiene que ser la misma, girada.
      final rotated = LashMappingPainter.layoutFor(
        EyeTrackingPhotoPipeline.rotateFrame180(f)!,
        styleId: 'cateye',
        leftEyeOffset: -offset,
      );
      Offset r(Offset p) => Offset(1000 - p.dx, 1000 - p.dy);
      expectOffsetsClose(rotated[0].bases, base[0].bases.map(r).toList());
    });
  });

  group('EyeShapeAnalyzer en rostro rotado', () {
    final upright = EyeShapeAnalyzer.analyze(uprightFace());

    test('vertical: mirada levemente elevada y simétrica', () {
      expect(upright.reliable, isTrue);
      expect(upright.leftTiltDeg, greaterThan(0));
      expect(upright.rightTiltDeg, greaterThan(0));
      expect(upright.asymmetry, lessThan(0.01));
    });

    for (final degrees in [90.0, -90.0, 180.0]) {
      test('${degrees.toInt()}°: mismas métricas que vertical', () {
        final a = EyeShapeAnalyzer.analyze(
          mapFrame(uprightFace(), rotation(degrees)),
        );
        expect(a.reliable, isTrue);
        expect(a.shape, upright.shape);
        expect(a.aspectRatio, closeTo(upright.aspectRatio, 1e-6));
        expect(a.leftTiltDeg, closeTo(upright.leftTiltDeg, 1e-6));
        expect(a.rightTiltDeg, closeTo(upright.rightTiltDeg, 1e-6));
        expect(a.asymmetry, closeTo(upright.asymmetry, 1e-6));
      });
    }
  });
}
