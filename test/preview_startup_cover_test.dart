import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/screens/widgets/preview_startup_cover.dart';
import 'package:Probador/screens/widgets/lash_loading_eye.dart';

void main() {
  Widget screen({required bool ready, String? error, VoidCallback? onBack}) =>
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const Text('Camera controls'),
              PreviewStartupCover(
                ready: ready,
                error: error,
                onBack: onBack ?? () {},
              ),
            ],
          ),
        ),
      );

  testWidgets('loading does not reveal itself after a fixed wait', (
    tester,
  ) async {
    await tester.pumpWidget(screen(ready: false));
    expect(find.text('Preparando el probador…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Preparando el probador…'), findsOneWidget);
    expect(find.byType(LashLoadingEye), findsOneWidget);
  });
  testWidgets('real readiness removes loading cover after transition', (
    tester,
  ) async {
    await tester.pumpWidget(screen(ready: false));
    await tester.pumpWidget(screen(ready: true));
    await tester.pumpAndSettle();
    expect(find.text('Preparando el probador…'), findsNothing);
    expect(find.byType(LashLoadingEye), findsNothing);
    expect(
      tester.widget<IgnorePointer>(find.byType(IgnorePointer).last).ignoring,
      isTrue,
    );
  });
  testWidgets('failure replaces progress and lets user leave', (tester) async {
    var left = false;
    await tester.pumpWidget(
      screen(
        ready: false,
        error: 'Permiso de cámara denegado',
        onBack: () => left = true,
      ),
    );
    expect(find.byType(LashLoadingEye), findsNothing);
    expect(find.text('Permiso de cámara denegado'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver'));
    expect(left, isTrue);
  });
}
