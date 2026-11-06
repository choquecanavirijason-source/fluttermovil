import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/lashes/cat_eye_recipe.dart';
import 'package:Probador/lashes/cat_eye_recipe_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'resolve completes, shares in-flight work, then reuses both cached files',
    () async {
      final dir = await Directory.systemTemp.createTemp('cateye_cache_test_');
      addTearDown(() => dir.delete(recursive: true));
      final cache = CatEyeRecipeCache(directoryProvider: () async => dir);
      const recipe = CatEyeRecipe();
      final first = cache.resolve(recipe);
      expect(identical(first, cache.resolve(recipe)), isTrue);
      final paths = await first.timeout(const Duration(seconds: 5));
      expect(await File(paths.left).length(), greaterThan(1000));
      expect(await File(paths.right).length(), greaterThan(1000));
      final modified = await File(paths.left).lastModified();
      expect(
        await cache.resolve(recipe).timeout(const Duration(seconds: 5)),
        paths,
      );
      expect(await File(paths.left).lastModified(), modified);
    },
  );

  test('failure completes and allows the same recipe to be retried', () async {
    final dir = await Directory.systemTemp.createTemp('cateye_retry_test_');
    addTearDown(() => dir.delete(recursive: true));
    var attempts = 0;
    final cache = CatEyeRecipeCache(
      directoryProvider: () async {
        if (attempts++ == 0) throw const FileSystemException('test failure');
        return dir;
      },
    );
    const recipe = CatEyeRecipe();
    await expectLater(
      cache.resolve(recipe).timeout(const Duration(seconds: 5)),
      throwsA(isA<FileSystemException>()),
    );
    final paths = await cache
        .resolve(recipe)
        .timeout(const Duration(seconds: 5));
    expect(await File(paths.left).exists(), isTrue);
    expect(attempts, 2);
  });
}
