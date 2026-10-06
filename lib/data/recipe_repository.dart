import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/backup.dart';
import '../domain/planner.dart';
import '../domain/recipe.dart';

abstract class RecipeRepository {
  Future<List<Recipe>> loadRecipes();
  Future<MealPlan?> loadPlan();
  Future<void> savePlan(MealPlan plan);
  Future<Set<String>> loadFavorites();
  Future<void> setFavorite(String recipeId, bool favorite);
  Future<List<SavedWeek>> loadSavedWeeks();
  Future<void> saveWeek(SavedWeek week);
  Future<void> renameWeek(String id, String name);
  Future<void> deleteWeek(String id);
  Future<AppBackup> exportBackup();

  /// Remplace la semaine courante, les favoris et les semaines enregistrées.
  Future<void> importBackup(AppBackup backup);
}

class LocalRecipeRepository implements RecipeRepository {
  LocalRecipeRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  Database? _db;
  SharedPreferences? _preferences;
  bool get _useSqlite =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  Future<void> _initialize() async {
    if (_useSqlite && _db == null) {
      final directory = await getDatabasesPath();
      _db = await openDatabase(
        '$directory/ounje_mi.sqlite3',
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createVersion2(db);
            // La table plans ne garde désormais que la semaine courante.
            await db.execute(
              'DELETE FROM plans WHERE id NOT IN (SELECT id FROM plans ORDER BY created_at DESC LIMIT 1)',
            );
          }
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE recipes (id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE foods (id TEXT PRIMARY KEY, food_group TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE recipe_foods (recipe_id TEXT REFERENCES recipes(id) ON DELETE CASCADE, food_id TEXT REFERENCES foods(id), PRIMARY KEY(recipe_id,food_id))',
          );
          await db.execute('CREATE INDEX food_lookup ON recipe_foods(food_id)');
          await db.execute(
            'CREATE TABLE ingredient_lines (recipe_id TEXT REFERENCES recipes(id) ON DELETE CASCADE, position INTEGER, raw TEXT NOT NULL, quantity REAL, unit TEXT, PRIMARY KEY(recipe_id,position))',
          );
          await db.execute(
            'CREATE TABLE recipe_steps (recipe_id TEXT REFERENCES recipes(id) ON DELETE CASCADE, position INTEGER, source_number INTEGER, text TEXT NOT NULL, PRIMARY KEY(recipe_id,position))',
          );
          await db.execute(
            'CREATE TABLE plans (id TEXT PRIMARY KEY, created_at TEXT NOT NULL, payload TEXT NOT NULL)',
          );
          await _createVersion2(db);
        },
      );
    } else if (!_useSqlite && _preferences == null) {
      _preferences = await SharedPreferences.getInstance();
    }
  }

  Future<void> _createVersion2(Database db) async {
    // Pas de clé étrangère vers recipes : le catalogue est vidé puis réimporté
    // quand le JSON change, et les favoris doivent y survivre.
    await db.execute('CREATE TABLE favorites (recipe_id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE saved_weeks (id TEXT PRIMARY KEY, name TEXT NOT NULL, saved_at TEXT NOT NULL, payload TEXT NOT NULL)',
    );
  }

  List<dynamic> _webWeeks() {
    final json = _preferences!.getString('ounje_mi_saved_weeks');
    if (json == null) return [];
    try {
      final decoded = jsonDecode(json);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeWebWeeks(List<dynamic> weeks) async {
    if (!await _preferences!.setString(
      'ounje_mi_saved_weeks',
      jsonEncode(weeks),
    )) {
      throw StateError('La sauvegarde locale a échoué.');
    }
  }

  @override
  Future<List<Recipe>> loadRecipes() async {
    await _initialize();
    final asset = await _bundle.loadString('assets/data/recipes.json');
    if (!_useSqlite) return decodeRecipes(asset);
    // Une comparaison du JSON permet d'importer les corrections futures sans effacer les menus.
    final current = await _db!.query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['catalog'],
    );
    if (current.isEmpty || current.first['value'] != asset) {
      final recipes = decodeRecipes(asset);
      await _db!.transaction((txn) async {
        await txn.delete('recipe_foods');
        await txn.delete('ingredient_lines');
        await txn.delete('recipe_steps');
        await txn.delete('recipes');
        await txn.delete('foods');
        final batch = txn.batch();
        for (final recipe in recipes) {
          batch.insert('recipes', {
            'id': recipe.id,
            'title': recipe.title,
            'category': recipe.category,
            'payload': jsonEncode(recipe.source),
          });
          for (final ingredient in recipe.ingredients) {
            for (final food in ingredient.foods) {
              batch.insert(
                  'foods',
                  {
                    'id': food.id,
                    'food_group': food.group,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
              batch.insert(
                  'recipe_foods',
                  {
                    'recipe_id': recipe.id,
                    'food_id': food.id,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
          for (var i = 0; i < recipe.ingredients.length; i++) {
            final ingredient = recipe.ingredients[i];
            batch.insert('ingredient_lines', {
              'recipe_id': recipe.id,
              'position': i,
              'raw': ingredient.raw,
              'quantity': ingredient.quantity,
              'unit': ingredient.unit,
            });
          }
          for (var i = 0; i < recipe.steps.length; i++) {
            final step = recipe.steps[i];
            batch.insert('recipe_steps', {
              'recipe_id': recipe.id,
              'position': i,
              'source_number': step.number,
              'text': step.text,
            });
          }
        }
        batch.insert(
            'metadata',
            {
              'key': 'catalog',
              'value': asset,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        await batch.commit(noResult: true);
      });
    }
    final rows = await _db!.query('recipes', orderBy: 'id');
    return rows
        .map(
          (r) => Recipe.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<MealPlan?> loadPlan() async {
    await _initialize();
    String? json;
    if (_useSqlite) {
      final rows = await _db!.query(
        'plans',
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) json = rows.first['payload'] as String;
    } else {
      json = _preferences!.getString('ounje_mi_latest_plan');
    }
    return json == null
        ? null
        : MealPlan.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  Future<void> savePlan(MealPlan plan) async {
    await _initialize();
    final payload = jsonEncode(plan.toJson());
    if (_useSqlite) {
      await _db!.transaction((txn) async {
        await txn.delete('plans');
        await txn.insert('plans', {
          'id': plan.id,
          'created_at': plan.createdAt.toIso8601String(),
          'payload': payload,
        });
      });
    } else if (!await _preferences!.setString(
      'ounje_mi_latest_plan',
      payload,
    )) {
      throw StateError('La sauvegarde locale a échoué.');
    }
  }

  @override
  Future<Set<String>> loadFavorites() async {
    await _initialize();
    if (!_useSqlite) {
      return (_preferences!.getStringList('ounje_mi_favorites') ?? []).toSet();
    }
    final rows = await _db!.query('favorites');
    return rows.map((r) => r['recipe_id'] as String).toSet();
  }

  @override
  Future<void> setFavorite(String recipeId, bool favorite) async {
    await _initialize();
    if (_useSqlite) {
      if (favorite) {
        await _db!.insert(
            'favorites',
            {
              'recipe_id': recipeId,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        await _db!.delete(
          'favorites',
          where: 'recipe_id = ?',
          whereArgs: [recipeId],
        );
      }
      return;
    }
    final favorites =
        (_preferences!.getStringList('ounje_mi_favorites') ?? []).toSet();
    if (favorite) {
      favorites.add(recipeId);
    } else {
      favorites.remove(recipeId);
    }
    if (!await _preferences!.setStringList(
      'ounje_mi_favorites',
      favorites.toList()..sort(),
    )) {
      throw StateError('La sauvegarde locale a échoué.');
    }
  }

  @override
  Future<List<SavedWeek>> loadSavedWeeks() async {
    await _initialize();
    final weeks = <SavedWeek>[];
    if (_useSqlite) {
      for (final row in await _db!.query('saved_weeks')) {
        // Une semaine illisible est ignorée sans faire échouer la liste.
        try {
          weeks.add(
            SavedWeek(
              id: row['id'] as String,
              name: row['name'] as String,
              savedAt: DateTime.parse(row['saved_at'] as String),
              plan: MealPlan.fromJson(
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              ),
            ),
          );
        } catch (_) {}
      }
    } else {
      for (final entry in _webWeeks()) {
        try {
          weeks.add(
            SavedWeek.fromJson(Map<String, dynamic>.from(entry as Map)),
          );
        } catch (_) {}
      }
    }
    return weeks..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  @override
  Future<void> saveWeek(SavedWeek week) async {
    await _initialize();
    if (_useSqlite) {
      await _db!.insert(
          'saved_weeks',
          {
            'id': week.id,
            'name': week.name,
            'saved_at': week.savedAt.toIso8601String(),
            'payload': jsonEncode(week.plan.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await _writeWebWeeks([
        ..._webWeeks().where((e) => e is! Map || e['id'] != week.id),
        week.toJson(),
      ]);
    }
  }

  @override
  Future<void> renameWeek(String id, String name) async {
    await _initialize();
    if (_useSqlite) {
      await _db!.update(
        'saved_weeks',
        {'name': name},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await _writeWebWeeks([
        for (final e in _webWeeks())
          e is Map && e['id'] == id ? {...e, 'name': name} : e,
      ]);
    }
  }

  @override
  Future<void> deleteWeek(String id) async {
    await _initialize();
    if (_useSqlite) {
      await _db!.delete('saved_weeks', where: 'id = ?', whereArgs: [id]);
    } else {
      await _writeWebWeeks(
        _webWeeks().where((e) => e is! Map || e['id'] != id).toList(),
      );
    }
  }

  @override
  Future<AppBackup> exportBackup() async => AppBackup(
        savedAt: DateTime.now().toUtc(),
        plan: await loadPlan(),
        favorites: await loadFavorites(),
        savedWeeks: await loadSavedWeeks(),
      );

  @override
  Future<void> importBackup(AppBackup backup) async {
    await _initialize();
    final plan = backup.plan;
    if (_useSqlite) {
      // Une seule transaction : en cas d'échec, les données d'avant restent.
      await _db!.transaction((txn) async {
        await txn.delete('plans');
        await txn.delete('favorites');
        await txn.delete('saved_weeks');
        if (plan != null) {
          await txn.insert('plans', {
            'id': plan.id,
            'created_at': plan.createdAt.toIso8601String(),
            'payload': jsonEncode(plan.toJson()),
          });
        }
        for (final id in backup.favorites) {
          await txn.insert('favorites', {'recipe_id': id});
        }
        for (final week in backup.savedWeeks) {
          await txn.insert('saved_weeks', {
            'id': week.id,
            'name': week.name,
            'saved_at': week.savedAt.toIso8601String(),
            'payload': jsonEncode(week.plan.toJson()),
          });
        }
      });
      return;
    }
    await _writeWebWeeks(backup.savedWeeks.map((w) => w.toJson()).toList());
    final preferences = _preferences!;
    if (!await preferences.setStringList(
          'ounje_mi_favorites',
          backup.favorites.toList()..sort(),
        ) ||
        !await (plan == null
            ? preferences.remove('ounje_mi_latest_plan')
            : preferences.setString(
                'ounje_mi_latest_plan',
                jsonEncode(plan.toJson()),
              ))) {
      throw StateError('La sauvegarde locale a échoué.');
    }
  }
}
