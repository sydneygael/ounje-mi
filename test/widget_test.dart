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
  bool failFavorites = false;
  @override
  Future<Set<String>> loadFavorites() async => {...favorites};
  @override
  Future<void> setFavorite(String recipeId, bool favorite) async {
    if (failFavorites) throw StateError('test');
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

  group('favoris', () {
    const planner = WeeklyPlanner();
    Finder card(String title) => find.descendant(
          of: find.byType(Card),
          matching: find.text(title),
        );

    testWidgets('cœur depuis le catalogue puis filtre', (tester) async {
      final repository = FakeRepository();
      await tester.pumpWidget(OunjeMiApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter aux favoris').first);
      await tester.pumpAndSettle();
      expect(repository.favorites.length, 1);
      expect(find.byTooltip('Retirer des favoris'), findsOneWidget);
      await tester.tap(find.text('Favoris'));
      await tester.pumpAndSettle();
      expect(find.text('1 favori'), findsOneWidget);
      await tester.tap(find.byTooltip('Retirer des favoris'));
      await tester.pumpAndSettle();
      expect(repository.favorites, isEmpty);
      expect(find.textContaining('Aucun favori pour l\'instant'), findsOne);
    });
    testWidgets('catalogue et fiche sans débordement sur téléphone',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(OunjeMiApp(repository: FakeRepository()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favoris'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favoris'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Card).first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ajouter aux favoris'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('cœur depuis la fiche', (tester) async {
      final repository = FakeRepository();
      final first = (repository.recipes
              .where((r) => planner.matches(r, PlanOptions()))
              .toList()
            ..sort((a, b) => a.title.compareTo(b.title)))
          .first;
      await tester.pumpWidget(OunjeMiApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(card(first.title));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter aux favoris'));
      await tester.pumpAndSettle();
      expect(repository.favorites, {first.id});
      expect(find.byTooltip('Retirer des favoris'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retirer des favoris'), findsOneWidget);
    });
    testWidgets('le filtre ignore « Mes choix »', (tester) async {
      final repository = FakeRepository();
      final chicken = repository.recipes.firstWhere((r) => r.id == 'bm-176');
      repository.favorites.add(chicken.id);
      repository.saved =
          planner.generate(repository.recipes, PlanOptions(vegetarian: true));
      await tester.pumpWidget(OunjeMiApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), chicken.title);
      await tester.pumpAndSettle();
      expect(card(chicken.title), findsNothing);
      await tester.tap(find.text('Favoris'));
      await tester.pumpAndSettle();
      expect(card(chicken.title), findsOneWidget);
    });
    testWidgets('échec de sauvegarde : le cœur revient en arrière',
        (tester) async {
      final repository = FakeRepository()..failFavorites = true;
      await tester.pumpWidget(OunjeMiApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter aux favoris').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retirer des favoris'), findsNothing);
      expect(find.textContaining('Favori non enregistré'), findsOneWidget);
    });
    testWidgets('les favoris sont transmis au moteur', (tester) async {
      final repository = FakeRepository()..favorites.add('bm-176');
      await tester.pumpWidget(OunjeMiApp(repository: repository));
      await tester.pumpAndSettle();
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
      expect(repository.saved?.options.favoriteRecipes, {'bm-176'});
    });
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
