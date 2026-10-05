import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ounje_mi/data/recipe_repository.dart';
import 'package:ounje_mi/domain/planner.dart';
import 'package:ounje_mi/domain/recipe.dart';
import 'package:ounje_mi/main.dart';

class FakeRepository implements RecipeRepository {
  MealPlan? saved;
  final recipes = decodeRecipes(
    File('assets/data/recipes.json').readAsStringSync(),
  );
  @override
  Future<List<Recipe>> loadRecipes() async => recipes;
  @override
  Future<MealPlan?> loadPlan() async => saved;
  @override
  Future<void> savePlan(MealPlan plan) async {
    saved = plan;
  }

  final favorites = <String>{};
  final weeks = <SavedWeek>[];
  @override
  Future<Set<String>> loadFavorites() async => {...favorites};
  @override
  Future<void> setFavorite(String recipeId, bool favorite) async {
    favorite ? favorites.add(recipeId) : favorites.remove(recipeId);
  }

  @override
  Future<List<SavedWeek>> loadSavedWeeks() async =>
      [...weeks]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  @override
  Future<void> saveWeek(SavedWeek week) async {
    weeks
      ..removeWhere((w) => w.id == week.id)
      ..add(week);
  }

  @override
  Future<void> renameWeek(String id, String name) async {
    final index = weeks.indexWhere((w) => w.id == id);
    if (index < 0) return;
    final week = weeks[index];
    weeks[index] = SavedWeek(
      id: week.id,
      name: name,
      savedAt: week.savedAt,
      plan: week.plan,
    );
  }

  @override
  Future<void> deleteWeek(String id) async {
    weeks.removeWhere((w) => w.id == id);
  }
}

void main() {
  testWidgets('catalogue, génération et courses', (tester) async {
    final repository = FakeRepository();
    await tester.pumpWidget(OunjeMiApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('Ounjé Mi'), findsOneWidget);
    await tester.tap(find.text('Mes choix'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Proposer mes 14 repas'),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
    await tester.tap(find.text('Proposer mes 14 repas'));
    await tester.pumpAndSettle();
    expect(repository.saved?.meals.length, 14);
    expect(find.text('Ma semaine'), findsWidgets);
    await tester.tap(find.text('Courses'));
    await tester.pumpAndSettle();
    expect(find.text('Mes courses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('échec du chargement affiché', (tester) async {
    await tester.pumpWidget(OunjeMiApp(repository: FailingRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
  });
  testWidgets('une nouvelle proposition après restauration avance le seed',
      (tester) async {
    final repository = FakeRepository();
    repository.saved = const WeeklyPlanner()
        .generate(repository.recipes, PlanOptions(seed: 42));
    await tester.pumpWidget(OunjeMiApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ma semaine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouvelle proposition'));
    await tester.pumpAndSettle();
    expect(repository.saved?.options.seed, 43);
    expect(tester.takeException(), isNull);
  });
}

class FailingRepository implements RecipeRepository {
  @override
  Future<List<Recipe>> loadRecipes() async => throw StateError('test');
  @override
  Future<MealPlan?> loadPlan() async => null;
  @override
  Future<void> savePlan(MealPlan plan) async {}
  @override
  Future<Set<String>> loadFavorites() async => {};
  @override
  Future<void> setFavorite(String recipeId, bool favorite) async {}
  @override
  Future<List<SavedWeek>> loadSavedWeeks() async => [];
  @override
  Future<void> saveWeek(SavedWeek week) async {}
  @override
  Future<void> renameWeek(String id, String name) async {}
  @override
  Future<void> deleteWeek(String id) async {}
}
