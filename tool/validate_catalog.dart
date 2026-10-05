import 'dart:convert';
import 'dart:io';

import 'package:ounje_mi/domain/recipe.dart';

void main() {
  final recipes = decodeRecipes(
    File('assets/data/recipes.json').readAsStringSync(),
  );
  final ids = <String>{};
  for (final recipe in recipes) {
    if (!ids.add(recipe.id) ||
        recipe.ingredients.isEmpty ||
        recipe.steps.isEmpty ||
        recipe.servings == null) {
      throw StateError('Recette invalide : ${recipe.id}');
    }
    final photo = File(recipe.photoAsset);
    if (!photo.existsSync()) throw StateError('Photo manquante : ${recipe.id}');
    final bytes = photo.readAsBytesSync();
    if (bytes.length < 1000 || bytes[0] != 0xff || bytes[1] != 0xd8) {
      throw StateError('JPEG invalide : ${recipe.id}');
    }
  }
  final report = jsonDecode(
    File('assets/data/import-report.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  if (report['recipe_count'] != recipes.length) {
    throw StateError('Rapport incohérent.');
  }
  stdout.writeln('${recipes.length} recettes et photos vérifiées.');
}
