import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/screens/widgets/eye_tracking_design_menu_bar.dart';
import 'package:Probador/screens/widgets/eye_tracking_filter_row.dart';

void main() {
  testWidgets('selector keeps filters above thumbnails on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              EyeTrackingDesignMenuBar(
                designImages: const ['', '', ''],
                designOptions: const ['Cat Eye', 'prueba pestana', 'Wispy'],
                selectedDesign: 0,
                onOpenGrid: () {},
                onReset: () {},
                categoryTitle: 'Efecto',
                helperText: 'prueba pestana · personalizado',
                filters: EyeTrackingFilterRow(
                  selectedFilter: 0,
                  onSelect: (_) {},
                  embedded: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.text('RECOMENDADOS')).dy,
      lessThan(tester.getTopLeft(find.text('Cat Eye')).dy),
    );
  });
}
