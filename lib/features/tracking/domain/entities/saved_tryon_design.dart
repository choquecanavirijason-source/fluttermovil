import '../../../../lashes/lash_options.dart';
import '../../../../lashes/lash_render_profile.dart';

/// Diseño del probador guardado con una aplicación (`tryon_recipe`).
///
/// Lleva una copia de los parámetros resueltos, así se puede volver a aplicar
/// igual aunque después el estilo o sus opciones cambien en el administrador.
class SavedTryOnDesign {
  const SavedTryOnDesign({
    required this.styleKey,
    required this.styleName,
    required this.revision,
    required this.original,
    required this.length,
    required this.technique,
    required this.thickness,
    this.colorId = 0,
    this.colorName,
    this.colorHex,
    this.options,
    this.profile,
  });

  final String styleKey, styleName;
  final int revision;

  /// Guardado con el modelo original (sin receta procedural).
  final bool original;
  final int length, technique, thickness, colorId;
  final String? colorName;

  /// `#RRGGBB` guardado; `null` = negro aprobado.
  final String? colorHex;
  final ResolvedLashOptions? options;
  final LashRenderProfile? profile;

  String? get lengthName => options?.length.name;
  String? get techniqueName => options?.technique.name;
  String? get thicknessName => options?.thickness.name;

  /// `null` si la receta no se puede leer (guardada por una versión que no
  /// entendemos): la ficha la muestra solo como texto.
  static SavedTryOnDesign? tryParse(Map<String, dynamic>? m) {
    if (m == null) return null;
    try {
      final key = m['style_key'], name = m['style_name'];
      final selection = Map<String, dynamic>.from(m['selection'] as Map);
      if (key is! String || name is! String) return null;
      final resolvedRaw = m['resolved_options'];
      ResolvedLashOptions? options;
      LashOption? color;
      if (resolvedRaw is Map) {
        final resolved = Map<String, dynamic>.from(resolvedRaw);
        options = ResolvedLashOptions.fromJson(resolved);
        if (resolved['color'] is Map) {
          color = LashOption.fromJson(
            Map<String, dynamic>.from(resolved['color'] as Map),
            'color',
          );
        }
      }
      final profileRaw = m['profile'];
      final hex = color?.parameters['color'] as String?;
      return SavedTryOnDesign(
        styleKey: key,
        styleName: name,
        revision: m['revision'] as int? ?? 0,
        original: m['render_mode'] == 'original',
        length: selection['length'] as int,
        technique: selection['technique'] as int,
        thickness: selection['thickness'] as int,
        colorId: selection['color'] as int? ?? 0,
        colorName: color?.name,
        colorHex: hex == LashOptionCatalog.approvedBlack ? null : hex,
        options: options,
        profile: profileRaw is Map
            ? LashRenderProfile.fromJson(Map<String, dynamic>.from(profileRaw))
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}
