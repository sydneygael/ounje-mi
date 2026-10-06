import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ounje_mi/data/recipe_repository.dart';
import 'package:ounje_mi/domain/backup.dart';
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

  @override
  Future<AppBackup> exportBackup() async => AppBackup(
        savedAt: DateTime.utc(2026, 10, 5, 12),
        plan: saved,
        favorites: {...favorites},
        savedWeeks: [...weeks],
      );
  @override
  Future<void> importBackup(AppBackup backup) async {
    saved = backup.plan;
    favorites
      ..clear()
      ..addAll(backup.favorites);
    weeks
      ..clear()
      ..addAll(backup.savedWeeks);
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

  group('semaines enregistrées', () {
    const planner = WeeklyPlanner();
    SavedWeek model(FakeRepository repository, {String? missingRecipe}) {
      final plan = planner.generate(repository.recipes, PlanOptions(seed: 5));
      return SavedWeek(
        id: 'modèle',
        name: 'Semaine rapide',
        // Midi UTC : la date affichée ne dépend pas du fuseau de la machine.
        savedAt: DateTime.utc(2026, 10, 1, 12),
        plan: missingRecipe == null
            ? plan
            : MealPlan(
                id: plan.id,
                options: plan.options,
                unfilledSlots: plan.unfilledSlots,
                createdAt: plan.createdAt,
                meals: [
                  PlannedMeal(
                    day: 1,
                    mealType: plan.meals.first.mealType,
                    recipeId: missingRecipe,
                    servings: 2,
                  ),
                  ...plan.meals.skip(1),
                ],
              ),
      );
    }

    Future<void> openWeeks(WidgetTester tester, RecipeRepository r) async {
      await tester.pumpWidget(OunjeMiApp(repository: r));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ma semaine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mes semaines'));
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String action) async {
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }

    testWidgets('enregistrer demande un nom non vide', (tester) async {
      final repository = FakeRepository();
      repository.saved = planner.generate(repository.recipes, PlanOptions());
      await tester.pumpWidget(OunjeMiApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ma semaine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer cette semaine'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Enregistrer');
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byType(TextField), ' Semaine rapide ');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.weeks.single.name, 'Semaine rapide');
      expect(
        repository.weeks.single.plan.toJson(),
        repository.saved!.toJson(),
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('réutiliser remplace la semaine et garde le modèle',
        (tester) async {
      final repository = FakeRepository();
      final week = model(repository);
      repository.weeks.add(week);
      repository.saved = planner.generate(repository.recipes, PlanOptions());
      await openWeeks(tester, repository);
      await choose(tester, 'Réutiliser');
      await tester.tap(find.widgetWithText(FilledButton, 'Réutiliser'));
      await tester.pumpAndSettle();
      expect(
        repository.saved!.meals.map((m) => m.recipeId),
        week.plan.meals.map((m) => m.recipeId),
      );
      expect(repository.saved!.id, isNot(week.plan.id));
      expect(repository.weeks.single.plan.toJson(), week.plan.toJson());
      expect(find.text('Nouvelle proposition'), findsOneWidget);
      // La proposition suivante repart des réglages du modèle.
      await tester.tap(find.text('Nouvelle proposition'));
      await tester.pumpAndSettle();
      expect(repository.saved!.options.seed, 6);
    });
    testWidgets('réutiliser depuis une semaine vide', (tester) async {
      final repository = FakeRepository();
      repository.weeks.add(model(repository));
      await openWeeks(tester, repository);
      await choose(tester, 'Réutiliser');
      await tester.tap(find.widgetWithText(FilledButton, 'Réutiliser'));
      await tester.pumpAndSettle();
      expect(repository.saved?.meals.length, 14);
    });
    testWidgets('annuler la réutilisation ne change rien', (tester) async {
      final repository = FakeRepository();
      repository.weeks.add(model(repository));
      await openWeeks(tester, repository);
      await choose(tester, 'Réutiliser');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(repository.saved, isNull);
      expect(find.text('Semaine rapide'), findsOneWidget);
    });
    testWidgets('renommer puis supprimer avec confirmation', (tester) async {
      final repository = FakeRepository();
      repository.weeks.add(model(repository));
      await openWeeks(tester, repository);
      expect(find.textContaining('1er octobre 2026 · 14/14'), findsOneWidget);
      await choose(tester, 'Renommer');
      await tester.enterText(find.byType(TextField), 'Semaine légère');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();
      expect(repository.weeks.single.name, 'Semaine légère');
      expect(find.text('Semaine légère'), findsOneWidget);
      await choose(tester, 'Supprimer');
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(repository.weeks, isEmpty);
      expect(find.textContaining('Aucune semaine enregistrée'), findsOne);
      expect(tester.takeException(), isNull);
    });
    testWidgets('une recette retirée est signalée puis écartée',
        (tester) async {
      final repository = FakeRepository();
      repository.weeks.add(model(repository, missingRecipe: 'disparue'));
      await openWeeks(tester, repository);
      await tester.tap(find.text('Semaine rapide'));
      await tester.pumpAndSettle();
      expect(find.text('Recette retirée'), findsOneWidget);
      await choose(tester, 'Réutiliser');
      await tester.tap(find.widgetWithText(FilledButton, 'Réutiliser'));
      await tester.pumpAndSettle();
      expect(repository.saved!.meals.length, 13);
      expect(repository.saved!.unfilledSlots.length, 1);
      expect(find.text('Recette retirée du catalogue.'), findsOneWidget);
      await tester.tap(find.text('Courses'));
      await tester.pumpAndSettle();
      expect(find.text('Mes courses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('planning courant avec une recette retirée', (tester) async {
      final repository = FakeRepository();
      repository.saved = model(repository, missingRecipe: 'disparue').plan;
      await tester.pumpWidget(OunjeMiApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Courses'));
      await tester.pumpAndSettle();
      expect(find.text('Mes courses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('semaine et liste sans débordement sur téléphone',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = FakeRepository();
      repository.weeks.add(model(repository));
      repository.saved = planner.generate(repository.recipes, PlanOptions());
      await openWeeks(tester, repository);
      await tester.tap(find.text('Semaine rapide'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
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
  @override
  Future<AppBackup> exportBackup() async => throw StateError('test');
  @override
  Future<void> importBackup(AppBackup backup) async {}
}
