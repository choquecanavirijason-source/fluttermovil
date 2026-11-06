import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'cat_eye_recipe.dart';

List<Uint8List> _generatePair(Map<String, int> map) {
  final recipe = CatEyeRecipe.fromMap(map);
  return [
    buildCatEyeGlb(recipe, right: false),
    buildCatEyeGlb(recipe, right: true),
  ];
}

/// Generate only on selection, off the UI isolate, then reuse the cached pair.
class CatEyeRecipeCache {
  final Future<Directory> Function() _directoryProvider;

  CatEyeRecipeCache({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/cat_eye_recipes');
  final _pending = <String, Future<({String left, String right})>>{};
  Future<({String left, String right})> resolve(CatEyeRecipe recipe) =>
      _pending.putIfAbsent(
        recipe.key,
        () => _write(recipe).whenComplete(() {
          // Do not return remove(): its value is this very Future. Returning it
          // makes whenComplete await itself, so resolve never completes.
          _pending.remove(recipe.key);
        }),
      );

  Future<({String left, String right})> _write(CatEyeRecipe recipe) async {
    final dir = await _directoryProvider();
    await dir.create(recursive: true);
    final left = File('${dir.path}/${recipe.key}_left.glb');
    final right = File('${dir.path}/${recipe.key}_right.glb');
    if (!await left.exists() || !await right.exists()) {
      final bytes = await compute(_generatePair, recipe.toMap());
      await left.writeAsBytes(bytes[0], flush: true);
      await right.writeAsBytes(bytes[1], flush: true);
    }
    return (left: left.path, right: right.path);
  }
}
