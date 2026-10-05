import 'dart:convert';

class Food {
  const Food(this.id, this.group);
  final String id;
  final String group;
  String get label => id.replaceAll('-', ' ');
}

class Ingredient {
  Ingredient.fromJson(Map<String, dynamic> json)
      : raw = json['raw'] as String,
        description = json['description'] as String,
        quantity = (json['quantity'] as num?)?.toDouble(),
        unit = json['unit'] as String?,
        group = json['group'] as String,
        foods = (json['foods'] as List)
            .map((f) => Food(f['id'] as String, f['group'] as String))
            .toList();
  final String raw;
  final String description;
  final double? quantity;
  final String? unit;
  final String group;
  final List<Food> foods;
}

class RecipeStep {
  RecipeStep.fromJson(Map<String, dynamic> json)
      : number = json['number'] as int,
        text = json['text'] as String,
        component = json['component'] as String;
  final int number;
  final String text;
  final String component;
}

class Recipe {
  Recipe.fromJson(this.source)
      : id = source['id'] as String,
        title = source['title'] as String,
        category = source['category'] as String,
        servings = source['servings'] as int?,
        totalMinutes = source['total_minutes'] as int?,
        kcalPerServing = source['kcal_per_serving'] as int?,
        mealTypes = List<String>.from(source['meal_types'] as List),
        ingredients = (source['ingredients'] as List)
            .map(
                (i) => Ingredient.fromJson(Map<String, dynamic>.from(i as Map)))
            .toList(),
        steps = (source['steps'] as List)
            .map(
                (s) => RecipeStep.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList();
  final Map<String, dynamic> source;
  final String id;
  final String title;
  final String category;
  final int? servings;
  final int? totalMinutes;
  final int? kcalPerServing;
  final List<String> mealTypes;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;
  String get photoAsset => 'assets/photos/$id.jpg';
  List<String> get qualityFlags =>
      List<String>.from(source['quality_flags'] as List);
  List<int> get pdfPages =>
      List<int>.from(source['source']['pdf_pages'] as List);
  Set<String> get foodIds =>
      ingredients.expand((i) => i.foods).map((f) => f.id).toSet();
  Map<String, Set<String>> get foodGroups {
    final groups = <String, Set<String>>{};
    for (final food in ingredients.expand((i) => i.foods)) {
      groups.putIfAbsent(food.group, () => <String>{}).add(food.id);
    }
    return groups;
  }
}

List<Recipe> decodeRecipes(String json) => (jsonDecode(json) as List)
    .map((r) => Recipe.fromJson(Map<String, dynamic>.from(r as Map)))
    .toList();

const groupLabels = {
  'fruit': 'Fruits',
  'legume': 'Légumes',
  'feculent': 'Féculents',
  'legumineuse': 'Légumineuses',
  'proteine_animale': 'Protéines animales',
  'proteine_vegetale': 'Protéines végétales',
  'laitage': 'Laitages',
  'boisson_vegetale': 'Boissons végétales',
  'noix_graine': 'Noix et graines',
  'matiere_grasse': 'Matières grasses',
  'condiment': 'Condiments',
  'autre': 'Autres',
};
const mealLabels = {
  'petit_dejeuner': 'Petit-déjeuner',
  'dejeuner': 'Déjeuner',
  'diner': 'Dîner',
  'collation': 'Collation',
  'boisson': 'Boisson',
};
