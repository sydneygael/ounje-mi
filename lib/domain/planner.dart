import 'dart:math';

import 'recipe.dart';

enum SelectionMode { prefer, requireSelected, onlySelected }

class PlanOptions {
  PlanOptions({
    this.days = 7,
    this.servings = 2,
    this.mealTypes = const ['dejeuner', 'diner'],
    this.selectedFoods = const {},
    this.excludedFoods = const {},
    this.mode = SelectionMode.prefer,
    this.maxMinutes,
    this.vegetarian = false,
    this.maxRepeats = 1,
    this.seed = 0,
  });
  final int days;
  final int servings;
  final List<String> mealTypes;
  final Map<String, Set<String>> selectedFoods;
  final Set<String> excludedFoods;
  final SelectionMode mode;
  final int? maxMinutes;
  final bool vegetarian;
  final int maxRepeats;
  final int seed;
  Map<String, dynamic> toJson() => {
        'days': days,
        'servings': servings,
        'meal_types': mealTypes,
        'selected_foods': selectedFoods.map(
          (k, v) => MapEntry(k, v.toList()..sort()),
        ),
        'excluded_foods': excludedFoods.toList()..sort(),
        'mode': mode.name,
        'max_minutes': maxMinutes,
        'vegetarian': vegetarian,
        'max_repeats': maxRepeats,
        'seed': seed,
      };
  factory PlanOptions.fromJson(Map<String, dynamic> json) => PlanOptions(
        days: json['days'] as int,
        servings: json['servings'] as int,
        mealTypes: List<String>.from(json['meal_types'] as List),
        selectedFoods: (json['selected_foods'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, Set<String>.from(v as List)),
        ),
        excludedFoods: Set<String>.from(json['excluded_foods'] as List),
        mode: SelectionMode.values.byName(json['mode'] as String),
        maxMinutes: json['max_minutes'] as int?,
        vegetarian: json['vegetarian'] as bool,
        maxRepeats: json['max_repeats'] as int,
        seed: json['seed'] as int,
      );
}

class PlannedMeal {
  const PlannedMeal({
    required this.day,
    required this.mealType,
    required this.recipeId,
    required this.servings,
  });
  final int day;
  final String mealType;
  final String recipeId;
  final int servings;
  Map<String, dynamic> toJson() => {
        'day': day,
        'meal_type': mealType,
        'recipe_id': recipeId,
        'servings': servings,
      };
  factory PlannedMeal.fromJson(Map<String, dynamic> j) => PlannedMeal(
        day: j['day'] as int,
        mealType: j['meal_type'] as String,
        recipeId: j['recipe_id'] as String,
        servings: j['servings'] as int,
      );
}

class MealPlan {
  MealPlan({
    required this.id,
    required this.options,
    required this.meals,
    required this.unfilledSlots,
    required this.createdAt,
  });
  final String id;
  final PlanOptions options;
  final List<PlannedMeal> meals;
  final List<Map<String, dynamic>> unfilledSlots;
  final DateTime createdAt;
  bool get complete => unfilledSlots.isEmpty;
  Map<String, dynamic> toJson() => {
        'id': id,
        'options': options.toJson(),
        'meals': meals.map((m) => m.toJson()).toList(),
        'unfilled_slots': unfilledSlots,
        'created_at': createdAt.toIso8601String(),
      };
  factory MealPlan.fromJson(Map<String, dynamic> j) => MealPlan(
        id: j['id'] as String,
        options: PlanOptions.fromJson(j['options'] as Map<String, dynamic>),
        meals: (j['meals'] as List)
            .map((m) =>
                PlannedMeal.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
        unfilledSlots: (j['unfilled_slots'] as List)
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class ShoppingItem {
  ShoppingItem(this.description, this.unit, this.group, this.quantity);
  final String description;
  final String unit;
  final String group;
  double quantity;
  String get displayQuantity {
    final rounded = (quantity * 1000).round() / 1000;
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }
}

class ShoppingList {
  const ShoppingList(this.items, this.manualItems);
  final List<ShoppingItem> items;
  final List<String> manualItems;
}

class WeeklyPlanner {
  const WeeklyPlanner();

  bool matches(Recipe recipe, PlanOptions options) {
    if (recipe.servings == null ||
        recipe.ingredients.isEmpty ||
        recipe.steps.isEmpty) {
      return false;
    }
    if (recipe.foodIds.intersection(options.excludedFoods).isNotEmpty) {
      return false;
    }
    final animalFoods = recipe.foodGroups['proteine_animale'] ?? <String>{};
    if (options.vegetarian && animalFoods.difference({'oeuf'}).isNotEmpty) {
      return false;
    }
    if (options.maxMinutes != null &&
        (recipe.totalMinutes == null ||
            recipe.totalMinutes! > options.maxMinutes!)) {
      return false;
    }
    if (options.mode != SelectionMode.prefer) {
      for (final selection in options.selectedFoods.entries) {
        if (selection.value.isEmpty) continue;
        final present = recipe.foodGroups[selection.key] ?? <String>{};
        if (options.mode == SelectionMode.requireSelected &&
            present.intersection(selection.value).isEmpty) {
          return false;
        }
        if (options.mode == SelectionMode.onlySelected &&
            present.difference(selection.value).isNotEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  void validate(List<Recipe> recipes, PlanOptions options) {
    if (options.days < 1 ||
        options.days > 14 ||
        options.servings < 1 ||
        options.servings > 20 ||
        options.maxRepeats < 1 ||
        options.maxRepeats > 14 ||
        options.seed < 0 ||
        options.maxMinutes != null &&
            (options.maxMinutes! < 1 || options.maxMinutes! > 1440)) {
      throw ArgumentError(
        'Nombre de jours, portions, durée ou répétitions invalide.',
      );
    }
    if (options.mealTypes.isEmpty ||
        options.mealTypes.toSet().length != options.mealTypes.length ||
        options.mealTypes.any((m) => !mealLabels.containsKey(m))) {
      throw ArgumentError('Types de repas invalides.');
    }
    final known = <String, String>{};
    for (final r in recipes) {
      for (final food in r.ingredients.expand((i) => i.foods)) {
        known[food.id] = food.group;
      }
    }
    for (final selection in options.selectedFoods.entries) {
      if (!groupLabels.containsKey(selection.key) ||
          selection.value.any((id) => known[id] != selection.key)) {
        throw ArgumentError('Aliment inconnu ou mauvais groupe.');
      }
    }
    if (options.excludedFoods.any((id) => !known.containsKey(id))) {
      throw ArgumentError('Exclusion inconnue.');
    }
    final preferred = options.selectedFoods.values.expand((v) => v).toSet();
    if (preferred.intersection(options.excludedFoods).isNotEmpty) {
      throw ArgumentError('Un aliment est sélectionné et exclu.');
    }
  }

  MealPlan generate(List<Recipe> recipes, PlanOptions options) {
    validate(recipes, options);
    final random = Random(options.seed);
    final preferred = options.selectedFoods.values.expand((v) => v).toSet();
    final pool = recipes.where((r) => matches(r, options)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final used = <String, int>{};
    final meals = <PlannedMeal>[];
    final missing = <Map<String, dynamic>>[];
    for (var day = 1; day <= options.days; day++) {
      for (final mealType in options.mealTypes) {
        final candidates = pool
            .where(
              (r) =>
                  r.mealTypes.contains(mealType) &&
                  (used[r.id] ?? 0) < options.maxRepeats,
            )
            .toList()
          ..shuffle(random);
        if (candidates.isEmpty) {
          missing.add({
            'day': day,
            'meal_type': mealType,
            'reason':
                'Aucune recette ne respecte les contraintes ou les répétitions.',
          });
          continue;
        }
        int score(Recipe r) =>
            r.foodIds.intersection(preferred).length * 10 -
            (used[r.id] ?? 0) * 3;
        var best = candidates.first;
        for (final r in candidates.skip(1)) {
          if (score(r) > score(best)) best = r;
        }
        used[best.id] = (used[best.id] ?? 0) + 1;
        meals.add(
          PlannedMeal(
            day: day,
            mealType: mealType,
            recipeId: best.id,
            servings: options.servings,
          ),
        );
      }
    }
    final now = DateTime.now().toUtc();
    return MealPlan(
      id: '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}',
      options: options,
      meals: meals,
      unfilledSlots: missing,
      createdAt: now,
    );
  }

  ShoppingList shoppingList(MealPlan plan, List<Recipe> recipes) {
    final index = {for (final recipe in recipes) recipe.id: recipe};
    final items = <String, ShoppingItem>{};
    final manual = <String>[];
    for (final meal in plan.meals) {
      final recipe = index[meal.recipeId];
      if (recipe == null || recipe.servings == null) {
        throw StateError('Recette du planning introuvable.');
      }
      final scale = meal.servings / recipe.servings!;
      for (final ingredient in recipe.ingredients) {
        if (ingredient.quantity == null || ingredient.unit == null) {
          manual.add(
            'Jour ${meal.day} · ${mealLabels[meal.mealType]} : ${ingredient.raw} (×${scale.toStringAsFixed(2)})',
          );
          continue;
        }
        final key =
            '${ingredient.description.toLowerCase()}\u0000${ingredient.unit}';
        final item = items.putIfAbsent(
          key,
          () => ShoppingItem(
            ingredient.description,
            ingredient.unit!,
            ingredient.group,
            0,
          ),
        );
        item.quantity += ingredient.quantity! * scale;
      }
    }
    final sorted = items.values.toList()
      ..sort((a, b) {
        final group = a.group.compareTo(b.group);
        return group != 0 ? group : a.description.compareTo(b.description);
      });
    return ShoppingList(sorted, manual);
  }
}
