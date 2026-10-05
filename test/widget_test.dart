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
}
