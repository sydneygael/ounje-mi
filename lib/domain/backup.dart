import 'dart:convert';

import 'planner.dart';

/// Sauvegarde illisible : JSON invalide ou structure inattendue.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'Sauvegarde illisible : $message';
}

/// Sauvegarde écrite par une version plus récente de l'application.
class BackupTooRecentException implements Exception {
  const BackupTooRecentException(this.format);
  final int format;
  @override
  String toString() => 'Format de sauvegarde $format non pris en charge.';
}

/// Données propres à l'utilisateur : semaine courante, favoris et semaines
/// enregistrées. Le catalogue n'en fait pas partie.
class AppBackup {
  const AppBackup({
    required this.savedAt,
    required this.plan,
    required this.favorites,
    required this.savedWeeks,
    this.skippedWeeks = 0,
  });
  static const currentFormat = 1;
  final DateTime savedAt;
  final MealPlan? plan;
  final Set<String> favorites;
  final List<SavedWeek> savedWeeks;

  /// Semaines enregistrées indécodables, ignorées à la lecture.
  final int skippedWeeks;
  bool get isEmpty => plan == null && favorites.isEmpty && savedWeeks.isEmpty;

  Map<String, dynamic> toJson() => {
        'format': currentFormat,
        'saved_at': savedAt.toIso8601String(),
        'plan': plan?.toJson(),
        'favorites': favorites.toList()..sort(),
        'saved_weeks': savedWeeks.map((w) => w.toJson()).toList(),
      };

  factory AppBackup.fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    if (format is! int) throw const BackupFormatException('format absent.');
    // Aucune lecture partielle d'un format inconnu.
    if (format > currentFormat) throw BackupTooRecentException(format);
    final favorites = json['favorites'];
    final entries = json['saved_weeks'];
    if (favorites is! List || entries is! List) {
      throw const BackupFormatException('listes absentes.');
    }
    try {
      final weeks = <SavedWeek>[];
      var skipped = 0;
      for (final entry in entries) {
        // Une semaine illisible est ignorée sans faire échouer la lecture.
        try {
          weeks
              .add(SavedWeek.fromJson(Map<String, dynamic>.from(entry as Map)));
        } catch (_) {
          skipped++;
        }
      }
      final plan = json['plan'];
      return AppBackup(
        savedAt: DateTime.parse(json['saved_at'] as String),
        plan: plan == null
            ? null
            : MealPlan.fromJson(Map<String, dynamic>.from(plan as Map)),
        favorites: Set<String>.from(favorites),
        savedWeeks: weeks,
        skippedWeeks: skipped,
      );
    } catch (e) {
      throw BackupFormatException('$e');
    }
  }

  static AppBackup decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw BackupFormatException(e.message);
    }
    if (json is! Map) throw const BackupFormatException('objet attendu.');
    return AppBackup.fromJson(Map<String, dynamic>.from(json));
  }
}
