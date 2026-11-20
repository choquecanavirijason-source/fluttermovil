import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/core/recommendation/eye_shape_analyzer.dart';
import 'package:Probador/eye_tracking_model.dart';

void main() {
  test('classify local reference frames with the actual app analyzer', () {
    final input = Platform.environment['EYE_REFERENCE_FRAMES'];
    final output = Platform.environment['EYE_REFERENCE_RESULTS'];
    expect(input, isNotNull);
    expect(output, isNotNull);
    final document =
        jsonDecode(File(input!).readAsStringSync()) as Map<String, dynamic>;
    final rows = document['rows'] as List;
    for (final row in rows) {
      final frame = TrackingFrame.fromMap(
        Map<dynamic, dynamic>.from(row['frame'] as Map),
      );
      final result = EyeShapeAnalyzer.analyze(frame);
      row['analysis'] = {
        'reliable': result.reliable,
        'shape': result.reliable ? result.shape.catalogName : null,
        'aspect_ratio': result.reliable ? result.aspectRatio : null,
        'tilt_deg': result.reliable ? result.canthalTiltDeg : null,
        'openness': result.reliable ? result.openness : null,
        'asymmetry': result.reliable ? result.asymmetry : null,
      };
    }
    File(
      output!,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(document));
    expect(rows, isNotEmpty);
  });
}
