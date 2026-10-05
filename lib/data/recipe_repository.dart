import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/planner.dart';
import '../domain/recipe.dart';

abstract class RecipeRepository {
  Future<List<Recipe>> loadRecipes();
  Future<MealPlan?> loadPlan();
  Future<void> savePlan(MealPlan plan);
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
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
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
        },
      );
    } else if (!_useSqlite && _preferences == null) {
      _preferences = await SharedPreferences.getInstance();
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
      await _db!.insert(
          'plans',
          {
            'id': plan.id,
            'created_at': plan.createdAt.toIso8601String(),
            'payload': payload,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else if (!await _preferences!.setString(
      'ounje_mi_latest_plan',
      payload,
    )) {
      throw StateError('La sauvegarde locale a échoué.');
    }
  }
}
