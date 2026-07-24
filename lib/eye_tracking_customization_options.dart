/// Catálogo de imágenes/opciones placeholder del menú de personalización de
/// [EyeTrackingPage] (diseño / técnica / efecto / grosor). Datos hardcodeados
/// hasta que el catálogo remoto exponga estas categorías (hoy solo expone
/// `lashDesign` y `eyeType`, ver `catalogo_provider.dart`).
class LashCustomizationCatalog {
  const LashCustomizationCatalog._();

  static const List<String> compatibleImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
    'assets/p5.png',
  ];

  /// Solo assets declarados en pubspec (p6 existe; p7/p8 no).
  static const List<String> explorarImages = [
    'assets/p4.png',
    'assets/p5.png',
    'assets/p6.png',
  ];

  static const List<String> _designImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
  ];

  static const List<String> _designOptions = ['Medio', 'Ligero', 'Alto', 'Medio'];

  static const List<String> _techImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
  ];

  static const List<String> _techOptions = [
    'Clásica',
    'Volumen',
    'Mega Vol.',
    'Híbrido',
  ];

  static const List<String> _effectImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
  ];

  static const List<String> _effectOptions = [
    'Natural',
    'Cat Eye',
    'Muñeca',
    'Abierto',
  ];

  static const List<String> _thicknessImages = [
    'assets/p1.png',
    'assets/p2.png',
    'assets/p3.png',
    'assets/p4.png',
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
    'effect' => _effectImages,
    'thickness' => _thicknessImages,
    _ => _designImages,
  };

  static List<String> optionsFor(String? category) => switch (category) {
    'design' => _designOptions,
    'tech' => _techOptions,
    'effect' => _effectOptions,
    'thickness' => _thicknessOptions,
    _ => _designOptions,
  };

  static String titleFor(String? category) => switch (category) {
    'design' => 'Diseño',
    'tech' => 'Tecnología',
    'effect' => 'Efecto',
    'thickness' => 'Grosor',
    _ => '',
  };

  /// Opción seleccionada en cada categoría, formateada para las notas de
  /// guardado (`_saveToClient` en `EyeTrackingPage`).
  static String designOptionAt(int index) => _designOptions[index];
  static String techOptionAt(int index) => _techOptions[index];
  static String effectOptionAt(int index) => _effectOptions[index];
  static String thicknessOptionAt(int index) => _thicknessOptions[index];
}
