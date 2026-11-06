import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/screens/widgets/eye_tracking_design_menu_bar.dart';
import 'package:Probador/screens/widgets/eye_tracking_lash_modal.dart';

void main() {
  testWidgets('recipe menu applies choices and exposes restore original', (
    tester,
  ) async {
    int? selection;
    var restored = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              EyeTrackingDesignMenuBar(
                designImages: const [
                  'assets/cateye_options/length_0.png',
                  'assets/cateye_options/length_1.png',
                  'assets/cateye_options/length_2.png',
                ],
                designOptions: const ['Corto', 'Medio', 'Largo'],
                selectedDesign: -1,
                onSelectDesign: (i) => selection = i,
                onOpenGrid: () {},
                categoryTitle: 'Largo',
                helperText: 'Cat Eye original',
                onReset: () => restored = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Largo').last);
    expect(selection, 2);
    await tester.tap(find.text('Restaurar original'));
    expect(restored, true);
  });
  testWidgets('expanded menu selects a real option', (tester) async {
    int? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              EyeTrackingLashModal(
                designImages: const [
                  'assets/cateye_options/tech_0.png',
                  'assets/cateye_options/tech_2.png',
                ],
                designOptions: const ['Clásica', 'Mega Vol.'],
                onClose: () {},
                onSelect: (i) => selection = i,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mega Vol.'));
    expect(selection, 1);
  });
}
