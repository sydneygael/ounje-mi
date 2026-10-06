import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ounje_mi/domain/backup.dart';
import 'package:ounje_mi/domain/planner.dart';
import 'package:ounje_mi/domain/recipe.dart';

void main() {
  final recipes = decodeRecipes(
    File('assets/data/recipes.json').readAsStringSync(),
  );
  final plan = const WeeklyPlanner().generate(recipes, PlanOptions(seed: 3));
  SavedWeek week(String id) => SavedWeek(
        id: id,
        name: 'Semaine $id',
        savedAt: DateTime.utc(2026, 10, 1),
        plan: plan,
      );
  AppBackup backup({MealPlan? current}) => AppBackup(
        savedAt: DateTime.utc(2026, 10, 5, 18, 30),
        plan: current,
        favorites: {'bm-176', 'bm-114'},
        savedWeeks: [week('a'), week('b')],
      );

  test('aller-retour complet', () {
    final source = backup(current: plan);
    final restored = AppBackup.decode(jsonEncode(source.toJson()));
    expect(restored.toJson(), source.toJson());
    expect(restored.savedAt, source.savedAt);
    expect(restored.favorites, source.favorites);
    expect(restored.savedWeeks.map((w) => w.id), ['a', 'b']);
    expect(restored.skippedWeeks, 0);
    expect(restored.isEmpty, isFalse);
    expect(source.toJson()['favorites'], ['bm-114', 'bm-176']);
  });
  test('sauvegarde sans semaine courante', () {
    final restored = AppBackup.decode(jsonEncode(backup().toJson()));
    expect(restored.plan, isNull);
    expect(restored.isEmpty, isFalse);
    final empty = AppBackup(
      savedAt: DateTime.utc(2026),
      plan: null,
      favorites: const {},
      savedWeeks: const [],
    );
    expect(AppBackup.decode(jsonEncode(empty.toJson())).isEmpty, isTrue);
  });
  test('format absent ou non entier refusé', () {
    final json = backup().toJson();
    expect(
      () => AppBackup.fromJson({...json}..remove('format')),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => AppBackup.fromJson({...json, 'format': '1'}),
      throwsA(isA<BackupFormatException>()),
    );
  });
  test('format plus récent refusé avec une erreur distincte', () {
    expect(
      // Le reste du contenu n'est pas lu.
      () => AppBackup.fromJson({'format': 2, 'nouveau': true}),
      throwsA(isA<BackupTooRecentException>()),
    );
  });
  test('structure invalide refusée', () {
    final json = backup(current: plan).toJson();
    for (final broken in [
      {...json, 'saved_at': 'hier'},
      {...json, 'favorites': 'bm-176'},
      {...json}..remove('saved_weeks'),
      {
        ...json,
        'plan': {'id': 'cassé'},
      },
    ]) {
      expect(
        () => AppBackup.fromJson(broken),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });
  test('une semaine indécodable est ignorée et comptée', () {
    final json = backup().toJson();
    final restored = AppBackup.fromJson({
      ...json,
      'saved_weeks': [
        {'id': 'cassée'},
        week('a').toJson(),
        'texte',
      ],
    });
    expect(restored.savedWeeks.single.id, 'a');
    expect(restored.skippedWeeks, 2);
  });
  test('texte qui n\'est pas un objet JSON', () {
    for (final text in ['pas du json', '[]', '']) {
      expect(
        () => AppBackup.decode(text),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });
}
