/// Cat Eye options. Thumbnails are rendered from the generated meshes.
/// Effect choices come from the same local presets as the main carousel.
class LashCustomizationCatalog {
  const LashCustomizationCatalog._();

  static const List<String> _designImages = [
    'assets/cateye_options/length_0.png',
    'assets/cateye_options/length_1.png',
    'assets/cateye_options/length_2.png',
  ];

  static const List<String> _designOptions = ['Corto', 'Medio', 'Largo'];

  static const List<String> _techImages = [
    'assets/cateye_options/tech_0.png',
    'assets/cateye_options/tech_1.png',
    'assets/cateye_options/tech_2.png',
    'assets/cateye_options/tech_3.png',
  ];

  static const List<String> _techOptions = [
    'Clásica',
    'Volumen',
    'Mega Vol.',
    'Híbrido',
  ];

  static const List<String> _thicknessImages = [
    'assets/cateye_options/thickness_0.png',
    'assets/cateye_options/thickness_1.png',
    'assets/cateye_options/thickness_2.png',
    'assets/cateye_options/thickness_3.png',
  ];

  static const List<String> _thicknessOptions = [
    '0.05mm',
    '0.07mm',
    '0.10mm',
    '0.15mm',
  ];

  static List<String> imagesFor(String? category) => switch (category) {
    'design' => _designImages,
    'tech' => _techImages,
    'thickness' => _thicknessImages,
    _ => _designImages,
  };

  static List<String> optionsFor(String? category) => switch (category) {
    'design' => _designOptions,
    'tech' => _techOptions,
    'thickness' => _thicknessOptions,
    _ => _designOptions,
  };

  static String titleFor(String? category) => switch (category) {
    'design' => 'Largo',
    'tech' => 'Técnica',
    'effect' => 'Efecto',
    'thickness' => 'Grosor',
    _ => '',
  };

  /// Opción seleccionada en cada categoría, formateada para las notas de
  /// guardado (`_saveToClient` en `EyeTrackingPage`).
  static String designOptionAt(int index) => _designOptions[index];
  static String techOptionAt(int index) => _techOptions[index];
  static String thicknessOptionAt(int index) => _thicknessOptions[index];
}
