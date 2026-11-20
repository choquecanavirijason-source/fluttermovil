import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/core/recommendation/eye_shape_analyzer.dart';
import 'package:Probador/core/recommendation/lash_consultation.dart';
import 'package:Probador/screens/widgets/eye_consultation_sheet.dart';

const analysis = EyeAnalysis(
  shape: EyeShape.almendrado,
  aspectRatio: 3,
  canthalTiltDeg: 5,
  openness: .33,
  asymmetry: .2,
  reliable: true,
  separationRatio: 1.2,
  leftAspectRatio: 3.3,
  rightAspectRatio: 2.7,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final visualCheck = Platform.environment['EYE_CONSULT_SCREENSHOT'] != null;
  setUpAll(() async {
    if (visualCheck) {
      final textFont = FontLoader('Arial')
        ..addFont(
          File(
            'C:/Windows/Fonts/arial.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            'C:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await textFont.load();
      await icons.load();
    }
  });
  testWidgets(
    'professional confirms attributes and objective on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      LashConsultation? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: visualCheck ? 'Arial' : null,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF094732),
            ),
          ),
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: Scaffold(
              body: EyeConsultationSheet(
                analysis: analysis,
                needsAdjustment: false,
                initial: const LashConsultation(),
                onApply: (value) => selected = value,
                onReanalyze: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Separados'), findsOneWidget);
      expect(find.text('Ascendente'), findsOneWidget);
      expect(find.text('Diferencia de apertura'), findsOneWidget);
      await tester.ensureVisible(find.text('Abrir la mirada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir la mirada'));
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<EyelidType>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<EyelidType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encapotado').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<EyeDepth>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<EyeDepth>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hundidos').last);
      await tester.pumpAndSettle();
      expect(find.text('Almendrado · Encapotado'), findsOneWidget);
      await tester.tap(find.text('Aplicar a sugerencias'));
      expect(selected?.eyelid, EyelidType.hooded);
      expect(selected?.depth, EyeDepth.deepSet);
      expect(selected?.goal, LashGoal.open);
      expect(selected?.toMap(analysis)['shape_source'], 'automatic');
      expect(selected?.toMap(analysis)['eyelid'], 'hooded');
      expect(find.textContaining('probable'), findsNothing);
      expect(tester.takeException(), isNull);
      final destination = Platform.environment['EYE_CONSULT_SCREENSHOT'];
      if (destination != null) {
        await tester.ensureVisible(find.text('Análisis de la mirada'));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(destination).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets(
    'ambiguous analysis offers positioning or professional shape confirmation',
    (tester) async {
      LashConsultation? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EyeConsultationSheet(
              analysis: null,
              needsAdjustment: true,
              initial: const LashConsultation(),
              onApply: (value) => selection = value,
              onReanalyze: () {},
            ),
          ),
        ),
      );
      expect(
        find.text('Ajusta la posición para analizar tu mirada'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Aplicar a sugerencias'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<EyeShape>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<EyeShape>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redondo').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar a sugerencias'));
      expect(selection?.shapeOverride, EyeShape.redondo);
      expect(selection?.toMap(null)['shape_source'], 'professional');
      expect(selection?.toMap(null)['aspect_ratio'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
