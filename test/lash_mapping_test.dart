import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/lash_mapping.dart';
import 'package:Probador/lashes/lash_options.dart';
import 'package:Probador/lashes/tryon_catalog.dart';

void main() {
  const rising = [
    (t: 0.0, length: .3),
    (t: .5, length: .45),
    (t: 1.0, length: .6),
  ];
  const corto = LashOption(0, 'Corto', {'scale': .78});
  const medio = LashOption(1, 'Medio', {'scale': 1.0});
  const largo = LashOption(2, 'Largo', {'scale': 1.23, 'map_offset_mm': 3});

  test('el mapeo del salón se desplaza entero con el largo', () {
    const style = TryOnStyle(
      key: 'anime',
      name: 'Anime',
      builtinStyle: 'anime',
      lashMap: [8, 9, 10, 9, 11, 12],
    );
    final m = resolveLashMap(style: style, length: medio)!;
    expect(m.labels, [8, 9, 10, 9, 11, 12]);
    expect(m.source, LashMapSource.salon);
    expect(resolveLashMap(style: style, length: corto)!.labels,
        [6, 7, 8, 7, 9, 10]);
    expect(resolveLashMap(style: style, length: largo)!.labels,
        [11, 12, 13, 12, 14, 15]);
  });

  test('sin mapeo del salón se calcula desde la forma con el pico del largo',
      () {
    const style = TryOnStyle(
      key: 'nuevo',
      name: 'Nuevo',
      builtinStyle: 'wispy',
      mapProfile: rising,
    );
    final m = resolveLashMap(style: style, length: medio)!;
    expect(m.source, LashMapSource.calculated);
    expect(m.labels.last, 12);
    expect(m.labels.first, greaterThanOrEqualTo(lashMapMinMm));
    expect(resolveLashMap(style: style, length: corto)!.labels.last, 10);
  });

  test('el cálculo nunca salta más de 1 mm entre zonas', () {
    // Forma de "prueba pestana": lagrimal muy corto y caída fuerte al final.
    const points = [
      (t: 0.0, length: .22),
      (t: .12, length: .32),
      (t: .25, length: .44),
      (t: .38, length: .55),
      (t: .5, length: .64),
      (t: .62, length: .72),
      (t: .75, length: .82),
      (t: .88, length: .86),
      (t: 1.0, length: .67),
    ];
    expect(computeLashMap(points, peakMm: 14), [10, 11, 12, 13, 14, 13]);
    expect(computeLashMap(points), [8, 9, 10, 11, 12, 11]);
    // La misma forma suavizada (lagrimal más alto, extremo que baja menos):
    // el pico cae entre zonas y aun así la zona más larga mide el pico.
    const smooth = [
      (t: 0.0, length: .34),
      (t: .12, length: .40),
      (t: .25, length: .48),
      (t: .38, length: .57),
      (t: .5, length: .65),
      (t: .62, length: .72),
      (t: .75, length: .80),
      (t: .88, length: .85),
      (t: 1.0, length: .79),
    ];
    expect(computeLashMap(smooth, peakMm: 14), [10, 11, 12, 13, 14, 14]);
    expect(computeLashMap(smooth), [8, 9, 10, 11, 12, 12]);
  });

  test('Cat Eye base usa el patrón validado', () {
    const style = TryOnStyle(key: 'cateye', name: 'Cat Eye', builtinStyle: 'cateye');
    expect(resolveLashMap(style: style, length: medio)!.labels,
        [9, 10, 11, 12, 13, 14]);
  });
}
