import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/eye_tracking_model.dart';
import 'package:Probador/eye_tracking_photo_pipeline.dart';

void main() {
  TrackingFrame frame() => const TrackingFrame(
    faceDetected: true,
    imageWidth: 100,
    imageHeight: 100,
    faceContour: [EyePoint(x: 10, y: 20)],
    leftEye: [EyePoint(x: 20, y: 30)],
    rightEye: [EyePoint(x: 80, y: 30)],
    leftIris: EyePoint(x: 25, y: 32),
    rightIris: EyePoint(x: 75, y: 32),
    leftOpenRatio: 0.8,
    rightOpenRatio: 0.7,
    leftUpperLid: [EyePoint(x: 20, y: 28)],
    leftLowerLid: [EyePoint(x: 20, y: 34)],
    rightUpperLid: [EyePoint(x: 80, y: 28)],
    rightLowerLid: [EyePoint(x: 80, y: 34)],
    leftLashLine: [EyePoint(x: 20, y: 27)],
    rightLashLine: [EyePoint(x: 80, y: 27)],
  );

  test('manual 180-degree rotation transforms every landmark reversibly', () {
    final original = frame();
    final rotated = EyeTrackingPhotoPipeline.rotateFrame180(original)!;
    final restored = EyeTrackingPhotoPipeline.rotateFrame180(rotated)!;

    expect(rotated.faceContour.single.toOffset().dx, 90);
    expect(rotated.faceContour.single.toOffset().dy, 80);
    expect(rotated.leftIris!.toOffset().dx, 75);
    expect(rotated.leftIris!.toOffset().dy, 68);
    expect(rotated.leftUpperLid.single.toOffset().dy, 72);
    expect(rotated.rightLashLine.single.toOffset().dx, 20);
    expect(
      restored.faceContour.single.toOffset(),
      original.faceContour.single.toOffset(),
    );
    expect(
      restored.leftEye.single.toOffset(),
      original.leftEye.single.toOffset(),
    );
    expect(
      restored.leftLashLine.single.toOffset(),
      original.leftLashLine.single.toOffset(),
    );
  });

  test(
    'inverted capture landmarks use the cropped, rotated eye-band space',
    () {
      final projected = EyeTrackingPhotoPipeline.frameForCapturedBand(
        frame(),
        const Size(100, 100),
        rotate180: true,
      )!;

      expect(projected.imageWidth, 200);
      expect(projected.imageHeight, 84);
      expect(projected.leftEye.single.toOffset().dx, 159);
      expect(projected.leftEye.single.toOffset().dy, 67);
    },
  );
}
