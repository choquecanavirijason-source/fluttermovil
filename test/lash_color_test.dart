import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/lash_options.dart';
import 'package:Probador/lashes/tryon_catalog.dart';
import 'package:Probador/screens/widgets/design_thumbnail_image.dart';

Map<String, dynamic> load(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map,
);

Map<String, dynamic> option(int id, String name, String color) => {
  'id': id,
  'name': name,
  'revision': 1,
  'sort_order': id,
  'is_active': true,
  'parameters': {'color': color},
};

void main() {
  test('catálogos sin colores ofrecen solo el negro aprobado', () {
    for (final name in ['tryon_catalog_v1.json', 'tryon_catalog_v2.json']) {
      final catalog = TryOnCatalog.fromJson(load(name));
      for (final style in catalog.styles) {
        expect(style.colors, [0]);
        expect(style.defaultColor, 0);
        expect(style.colorOptions.single.parameters['color'], '#111111');
      }
    }
  });

  test('lee la paleta publicada y los colores de cada estilo', () {
    final json = load('tryon_catalog_v2.json');
    (json['options'] as Map)['color'] = [
      option(0, 'Negro', '#111111'),
      option(1, 'Café', '#6b4226'),
      option(2, 'Borgoña', '#5A1A2B'),
    ];
    final style = (json['styles'] as List).first as Map;
    style['allowed_colors'] = [0, 2];
    (style['defaults'] as Map)['color'] = 2;
    final parsed = TryOnCatalog.fromJson(json).styles.first;
    expect(parsed.colors, [0, 2]);
    expect(parsed.defaultColor, 2);
    expect(parsed.colorOptions.map((o) => o.name), ['Negro', 'Borgoña']);
    // El código se normaliza a mayúsculas.
    expect(parsed.options.color(1).parameters['color'], '#6B4226');
  });

  test('rechaza colores inválidos y un inicial fuera de la lista', () {
    expect(
      () => LashOption.fromJson(option(1, 'Mal', 'cafe'), 'color'),
      throwsFormatException,
    );
    final json = load('tryon_catalog_v2.json');
    final style = (json['styles'] as List).first as Map;
    style['allowed_colors'] = [0];
    (style['defaults'] as Map)['color'] = 3;
    expect(
      () => TryOnStyle.fromJson(
        Map<String, dynamic>.from(style),
        options: LashOptionCatalog.bundled,
      ),
      throwsFormatException,
    );
  });

  test('la receta guarda el color solo si no es negro', () {
    final json = load('tryon_catalog_v2.json');
    (json['options'] as Map)['color'] = [
      option(0, 'Negro', '#111111'),
      option(4, 'Azul noche', '#1F2A4A'),
    ];
    final style = (json['styles'] as List).first as Map;
    style['allowed_colors'] = [0, 4];
    final parsed = TryOnCatalog.fromJson(json).styles.first;
    final black = parsed.snapshot();
    expect((black['selection'] as Map).containsKey('color'), isFalse);
    expect((black['resolved_options'] as Map).containsKey('color'), isFalse);
    final blue = parsed.snapshot(color: 4);
    expect((blue['selection'] as Map)['color'], 4);
    expect(
      ((blue['resolved_options'] as Map)['color'] as Map)['parameters'],
      {'color': '#1F2A4A'},
    );
  });

  testWidgets('las muestras de color se dibujan sin imágenes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DesignThumbnailImage(path: 'swatch:#5A1A2B', size: 40),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.image_not_supported), findsNothing);
    final box = tester.widget<Container>(find.byType(Container).last);
    final gradient =
        (box.decoration! as BoxDecoration).gradient! as RadialGradient;
    expect(gradient.colors.last, const Color(0xFF5A1A2B));
  });
}
