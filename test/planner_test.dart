import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ounje_mi/domain/planner.dart';
import 'package:ounje_mi/domain/recipe.dart';

void main() {
  final recipes = decodeRecipes(
    File('assets/data/recipes.json').readAsStringSync(),
  );
  const planner = WeeklyPlanner();

  test('146 recettes avec ingrédients, étapes et photos', () {
    expect(recipes.length, 146);
    expect(recipes.map((r) => r.id).toSet().length, 146);
    for (final r in recipes) {
      expect(r.ingredients, isNotEmpty);
      expect(r.steps, isNotEmpty);
      expect(File(r.photoAsset).existsSync(), isTrue);
    }
  });
  test('une semaine = 14 repas distincts', () {
    final plan = planner.generate(recipes, PlanOptions());
    expect(plan.complete, isTrue);
    expect(plan.meals.length, 14);
    expect(plan.meals.map((m) => m.recipeId).toSet().length, 14);
  });
  test('même seed, mêmes repas', () {
    final options = PlanOptions(
      seed: 42,
      selectedFoods: {
        'legume': {'brocoli'},
      },
    );
    expect(
      planner.generate(recipes, options).meals.map((m) => m.toJson()).toList(),
      planner.generate(recipes, options).meals.map((m) => m.toJson()).toList(),
    );
  });
  test('exclusions et durée toujours respectées', () {
    final excluded = {'saumon', 'thon', 'poulet', 'noix'};
    final options = PlanOptions(excludedFoods: excluded, maxMinutes: 25);
    final plan = planner.generate(recipes, options);
    for (final meal in plan.meals) {
      final r = recipes.firstWhere((r) => r.id == meal.recipeId);
      expect(r.foodIds.intersection(excluded), isEmpty);
      expect(r.totalMinutes, lessThanOrEqualTo(25));
    }
  });
  test('chaque groupe choisi est requis en mode strict', () {
    final plan = planner.generate(
      recipes,
      PlanOptions(
        days: 1,
        mode: SelectionMode.requireSelected,
        selectedFoods: {
          'feculent': {'quinoa'},
        },
      ),
    );
    expect(plan.meals, isNotEmpty);
    for (final meal in plan.meals) {
      expect(
        recipes.firstWhere((r) => r.id == meal.recipeId).foodIds,
        contains('quinoa'),
      );
    }
  });
  test('mode onlySelected interdit les autres aliments du groupe', () {
    final plan = planner.generate(
      recipes,
      PlanOptions(
        mode: SelectionMode.onlySelected,
        selectedFoods: {
          'feculent': {'quinoa'},
        },
      ),
    );
    for (final meal in plan.meals) {
      final r = recipes.firstWhere((r) => r.id == meal.recipeId);
      expect((r.foodGroups['feculent'] ?? {}).difference({'quinoa'}), isEmpty);
    }
  });
  test('planning impossible = créneaux vides explicites', () {
    final plan = planner.generate(recipes, PlanOptions(maxMinutes: 1));
    expect(plan.complete, isFalse);
    expect(plan.unfilledSlots.length, 14);
    expect(plan.meals, isEmpty);
  });
  test('végétarien exclut viandes, poissons et fruits de mer', () {
    final plan = planner.generate(
      recipes,
      PlanOptions(vegetarian: true, maxRepeats: 2),
    );
    for (final meal in plan.meals) {
      expect(
        (recipes
                    .firstWhere((r) => r.id == meal.recipeId)
                    .foodGroups['proteine_animale'] ??
                <String>{})
            .difference({'oeuf'}),
        isEmpty,
      );
    }
  });
  test('le filtre végétarien autorise les œufs', () {
    final omelette = recipes.firstWhere((r) => r.id == 'bm-114');
    expect(planner.matches(omelette, PlanOptions(vegetarian: true)), isTrue);
    final chicken = recipes.firstWhere((r) => r.id == 'bm-176');
    expect(planner.matches(chicken, PlanOptions(vegetarian: true)), isFalse);
  });
  test('portions et quantités manuelles', () {
    final recipe = recipes.firstWhere((r) => r.id == 'bm-176');
    final plan = MealPlan(
      id: 'test',
      options: PlanOptions(servings: 4),
      createdAt: DateTime.utc(2026),
      meals: [
        const PlannedMeal(
          day: 1,
          mealType: 'diner',
          recipeId: 'bm-176',
          servings: 4,
        ),
      ],
      unfilledSlots: [],
    );
    final shopping = planner.shoppingList(plan, [recipe]);
    expect(
      shopping.items
          .firstWhere((i) => i.description.contains('poulet'))
          .quantity,
      600,
    );
    expect(shopping.manualItems, isNotEmpty);
  });
  test('pas de fusion saumon frais et fumé', () {
    final a = Recipe.fromJson({
      ...recipes.first.source,
      'id': 'fresh',
      'ingredients': [
        {
          'raw': '100 g de saumon frais',
          'description': 'saumon frais',
          'quantity': 100,
          'unit': 'g',
          'group': 'proteine_animale',
          'foods': [],
        },
      ],
    });
    final b = Recipe.fromJson({
      ...recipes.first.source,
      'id': 'smoked',
      'ingredients': [
        {
          'raw': '100 g de saumon fumé',
          'description': 'saumon fumé',
          'quantity': 100,
          'unit': 'g',
          'group': 'proteine_animale',
          'foods': [],
        },
      ],
    });
    final plan = MealPlan(
      id: 'test',
      options: PlanOptions(),
      createdAt: DateTime.utc(2026),
      unfilledSlots: [],
      meals: [
        PlannedMeal(
          day: 1,
          mealType: 'dejeuner',
          recipeId: a.id,
          servings: a.servings!,
        ),
        PlannedMeal(
          day: 1,
          mealType: 'diner',
          recipeId: b.id,
          servings: b.servings!,
        ),
      ],
    );
    expect(planner.shoppingList(plan, [a, b]).items.length, 2);
  });
  test('validation des options', () {
    for (final options in [
      PlanOptions(days: 0),
      PlanOptions(servings: 0),
      PlanOptions(mealTypes: ['diner', 'diner']),
      PlanOptions(
        selectedFoods: {
          'fruit': {'brocoli'},
        },
      ),
      PlanOptions(excludedFoods: {'imaginaire'}),
      PlanOptions(
        selectedFoods: {
          'legume': {'brocoli'},
        },
        excludedFoods: {'brocoli'},
      ),
    ]) {
      expect(() => planner.generate(recipes, options), throwsArgumentError);
    }
  });
  test('planning sérialisable en JSON sans perte', () {
    final plan = planner.generate(recipes, PlanOptions());
    final reloaded = MealPlan.fromJson(
      jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
    );
    expect(reloaded.toJson(), plan.toJson());
  });
  test('recette sur deux pages et durée nocturne inconnue', () {
    expect(recipes.firstWhere((r) => r.id == 'bm-176').pdfPages, [177, 178]);
    expect(recipes.firstWhere((r) => r.id == 'bm-091').totalMinutes, isNull);
  });
}
