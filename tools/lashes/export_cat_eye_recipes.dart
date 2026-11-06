import 'dart:io';
import '../../lib/lashes/cat_eye_recipe.dart';

void main() {
  final out = Directory('build/cateye_recipes');
  out.createSync(recursive: true);
  for (var l = 0; l < 3; l++) {
    for (var t = 0; t < 4; t++) {
      for (var d = 0; d < 4; d++) {
        final recipe = CatEyeRecipe(length: l, technique: t, thickness: d);
        for (final right in [false, true]) {
          File(
            '${out.path}/${recipe.key}_${right ? 'right' : 'left'}.glb',
          ).writeAsBytesSync(buildCatEyeGlb(recipe, right: right));
        }
      }
    }
  }
}
