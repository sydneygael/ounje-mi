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
  group('favoris', () {
    // Une recette réservée au dîner : elle ne peut pas partir au déjeuner.
    final dinnerOnly = recipes
        .where(
          (r) =>
              r.mealTypes.contains('diner') &&
              !r.mealTypes.contains('dejeuner') &&
              planner.matches(r, PlanOptions()),
        )
        .toList();
    String dinnerOf(MealPlan plan, int day) => plan.meals
        .firstWhere((m) => m.day == day && m.mealType == 'diner')
        .recipeId;

    test('un favori est choisi à score égal', () {
      final favorite = dinnerOnly.first.id;
      for (var seed = 0; seed < 10; seed++) {
        final plan = planner.generate(
          recipes,
          PlanOptions(days: 1, seed: seed, favoriteRecipes: {favorite}),
        );
        expect(dinnerOf(plan, 1), favorite);
      }
    });
    test('un aliment préféré pèse plus qu\'un favori', () {
      final favorite =
          dinnerOnly.firstWhere((r) => !r.foodIds.contains('brocoli')).id;
      expect(dinnerOnly.any((r) => r.foodIds.contains('brocoli')), isTrue);
      final plan = planner.generate(
        recipes,
        PlanOptions(
          days: 1,
          favoriteRecipes: {favorite},
          selectedFoods: {
            'legume': {'brocoli'},
          },
        ),
      );
      final dinner = recipes.firstWhere((r) => r.id == dinnerOf(plan, 1));
      expect(dinner.foodIds, contains('brocoli'));
    });
    test('un favori exclu n\'est jamais servi', () {
      final chicken = recipes.firstWhere((r) => r.id == 'bm-176');
      expect(chicken.foodIds, contains('poulet'));
      final plan = planner.generate(
        recipes,
        PlanOptions(favoriteRecipes: {chicken.id}, excludedFoods: {'poulet'}),
      );
      expect(plan.meals.map((m) => m.recipeId), isNot(contains(chicken.id)));
    });
    test('un favori n\'est pas répété avant les autres recettes', () {
      final favorite = dinnerOnly.first.id;
      final plan = planner.generate(
        recipes,
        PlanOptions(maxRepeats: 2, favoriteRecipes: {favorite}),
      );
      expect(plan.meals.where((m) => m.recipeId == favorite).length, 1);
    });
    test('un favori inconnu est ignoré', () {
      List<Map<String, dynamic>> meals(Set<String> favorites) => planner
          .generate(recipes, PlanOptions(seed: 7, favoriteRecipes: favorites))
          .meals
          .map((m) => m.toJson())
          .toList();
      expect(meals({'imaginaire'}), meals({}));
    });
    test('les options sans favoris enregistrés se relisent', () {
      final json = PlanOptions().toJson()..remove('favorite_recipes');
      expect(PlanOptions.fromJson(json).favoriteRecipes, isEmpty);
    });
  });
  test('semaine enregistrée sérialisable en JSON sans perte', () {
    final week = SavedWeek(
      id: 'w1',
      name: 'Semaine rapide',
      savedAt: DateTime.utc(2026, 10, 5),
      plan: planner.generate(recipes, PlanOptions()),
    );
    final reloaded = SavedWeek.fromJson(
      jsonDecode(jsonEncode(week.toJson())) as Map<String, dynamic>,
    );
    expect(reloaded.toJson(), week.toJson());
  });
  test('reconcile vide les créneaux des recettes retirées', () {
    final plan = planner.generate(recipes, PlanOptions());
    expect(identical(planner.reconcile(plan, recipes), plan), isTrue);
    final removed = plan.meals.first;
    final remaining = recipes.where((r) => r.id != removed.recipeId).toList();
    expect(() => planner.shoppingList(plan, remaining), throwsStateError);
    final reconciled = planner.reconcile(plan, remaining);
    expect(reconciled.meals.length, 13);
    expect(reconciled.unfilledSlots.single['day'], removed.day);
    expect(reconciled.unfilledSlots.single['meal_type'], removed.mealType);
    expect(planner.shoppingList(reconciled, remaining).items, isNotEmpty);
  });
  test('recette sur deux pages et durée nocturne inconnue', () {
    expect(recipes.firstWhere((r) => r.id == 'bm-176').pdfPages, [177, 178]);
    expect(recipes.firstWhere((r) => r.id == 'bm-091').totalMinutes, isNull);
  });
}
