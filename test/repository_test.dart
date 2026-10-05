import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ounje_mi/data/recipe_repository.dart';
import 'package:ounje_mi/domain/planner.dart';
import 'package:ounje_mi/domain/recipe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('le repository charge les 146 recettes embarquées', () async {
    final repository = LocalRecipeRepository();
    expect((await repository.loadRecipes()).length, 146);
    expect(await repository.loadPlan(), isNull);
  });
  test(
    'le dernier planning survit à une nouvelle instance du repository',
    () async {
      final repository = LocalRecipeRepository();
      final recipes = await repository.loadRecipes();
      final plan = const WeeklyPlanner().generate(recipes, PlanOptions());
      await repository.savePlan(plan);
      final restored = await LocalRecipeRepository().loadPlan();
      expect(restored?.toJson(), plan.toJson());
    },
  );

  // Les mêmes scénarios valent pour le stockage web et pour SQLite.
  void sharedScenarios() {
    test('les favoris survivent à une nouvelle instance', () async {
      final repository = LocalRecipeRepository();
      expect(await repository.loadFavorites(), isEmpty);
      await repository.setFavorite('bm-176', true);
      await repository.setFavorite('bm-176', true);
      await repository.setFavorite('bm-114', true);
      await repository.setFavorite('bm-114', false);
      expect(await LocalRecipeRepository().loadFavorites(), {'bm-176'});
    });
    test('semaines enregistrées, renommées et supprimées', () async {
      final repository = LocalRecipeRepository();
      final recipes = await repository.loadRecipes();
      final plan = const WeeklyPlanner().generate(recipes, PlanOptions());
      SavedWeek week(String id, int day) => SavedWeek(
            id: id,
            name: 'Semaine $id',
            savedAt: DateTime.utc(2026, 10, day),
            plan: plan,
          );
      expect(await repository.loadSavedWeeks(), isEmpty);
      await repository.saveWeek(week('a', 1));
      await repository.saveWeek(week('b', 2));
      await repository.renameWeek('a', 'Semaine rapide');
      final weeks = await LocalRecipeRepository().loadSavedWeeks();
      expect(weeks.map((w) => w.id), ['b', 'a']);
      expect(weeks.last.name, 'Semaine rapide');
      expect(weeks.last.plan.toJson(), plan.toJson());
      await repository.deleteWeek('b');
      expect((await repository.loadSavedWeeks()).map((w) => w.id), ['a']);
      // Enregistrer une semaine ne touche pas la semaine courante.
      expect(await repository.loadPlan(), isNull);
    });
  }

  group('stockage web', () {
    sharedScenarios();
    test('une semaine illisible est ignorée et conservée', () async {
      final repository = LocalRecipeRepository();
      final recipes = await repository.loadRecipes();
      final week = SavedWeek(
        id: 'a',
        name: 'Semaine a',
        savedAt: DateTime.utc(2026, 10, 1),
        plan: const WeeklyPlanner().generate(recipes, PlanOptions()),
      );
      SharedPreferences.setMockInitialValues({
        'ounje_mi_saved_weeks': jsonEncode([
          {'id': 'cassée'},
          week.toJson(),
        ]),
      });
      final fresh = LocalRecipeRepository();
      expect((await fresh.loadSavedWeeks()).map((w) => w.id), ['a']);
      await fresh.renameWeek('a', 'Renommée');
      final preferences = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(preferences.getString('ounje_mi_saved_weeks')!) as List;
      expect(stored.length, 2);
      expect((await fresh.loadSavedWeeks()).single.name, 'Renommée');
    });
  });

  group('SQLite', () {
    late Directory directory;
    late String path;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      directory = Directory.systemTemp.createTempSync('ounje_mi_test');
      await databaseFactory.setDatabasesPath(directory.path);
      path = '${directory.path}/ounje_mi.sqlite3';
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });
    tearDown(() async {
      await databaseFactory.deleteDatabase(path);
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows peut garder le fichier verrouillé un instant.
      }
    });

    sharedScenarios();
    test('un seul planning courant est conservé', () async {
      final repository = LocalRecipeRepository();
      final recipes = await repository.loadRecipes();
      const planner = WeeklyPlanner();
      await repository.savePlan(planner.generate(recipes, PlanOptions()));
      final latest = planner.generate(recipes, PlanOptions(seed: 1));
      await repository.savePlan(latest);
      final db = await openDatabase(path);
      expect((await db.query('plans')).length, 1);
      expect((await repository.loadPlan())?.toJson(), latest.toJson());
    });
    test('les favoris survivent au réimport du catalogue', () async {
      final repository = LocalRecipeRepository();
      await repository.loadRecipes();
      await repository.setFavorite('bm-176', true);
      final db = await openDatabase(path);
      await db.update('metadata', {'value': 'ancien catalogue'});
      expect((await repository.loadRecipes()).length, 146);
      expect(await repository.loadFavorites(), {'bm-176'});
    });
    test('migration de la version 1 vers la version 2', () async {
      final old = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          for (final statement in [
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            'CREATE TABLE recipes (id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL, payload TEXT NOT NULL)',
            'CREATE TABLE foods (id TEXT PRIMARY KEY, food_group TEXT NOT NULL)',
            'CREATE TABLE recipe_foods (recipe_id TEXT REFERENCES recipes(id) ON DELETE CASCADE, food_id TEXT REFERENCES foods(id), PRIMARY KEY(recipe_id,food_id))',
            'CREATE INDEX food_lookup ON recipe_foods(food_id)',
            'CREATE TABLE ingredient_lines (recipe_id TEXT REFERENCES recipes(id) ON DELETE CASCADE, position INTEGER, raw TEXT NOT NULL, quantity REAL, unit TEXT, PRIMARY KEY(recipe_id,position))',
            'CREATE TABLE recipe_steps (recipe_id TEXT REFERENCES recipes(id) ON DELETE CASCADE, position INTEGER, source_number INTEGER, text TEXT NOT NULL, PRIMARY KEY(recipe_id,position))',
            'CREATE TABLE plans (id TEXT PRIMARY KEY, created_at TEXT NOT NULL, payload TEXT NOT NULL)',
          ]) {
            await db.execute(statement);
          }
        },
      );
      final recipes = decodeRecipes(
        File('assets/data/recipes.json').readAsStringSync(),
      );
      const planner = WeeklyPlanner();
      MealPlan dated(int seed, int day) {
        final plan = planner.generate(recipes, PlanOptions(seed: seed));
        return MealPlan(
          id: 'plan-$seed',
          options: plan.options,
          meals: plan.meals,
          unfilledSlots: plan.unfilledSlots,
          createdAt: DateTime.utc(2026, 9, day),
        );
      }

      final latest = dated(2, 20);
      for (final plan in [dated(1, 10), latest, dated(3, 15)]) {
        await old.insert('plans', {
          'id': plan.id,
          'created_at': plan.createdAt.toIso8601String(),
          'payload': jsonEncode(plan.toJson()),
        });
      }
      await old.close();

      final repository = LocalRecipeRepository();
      expect((await repository.loadPlan())?.toJson(), latest.toJson());
      final db = await openDatabase(path);
      expect(await db.getVersion(), 2);
      expect((await db.query('plans')).length, 1);
      expect(await repository.loadSavedWeeks(), isEmpty);
      await repository.setFavorite('bm-176', true);
      expect(await repository.loadFavorites(), {'bm-176'});
      expect((await repository.loadRecipes()).length, 146);
    });
  });
}
