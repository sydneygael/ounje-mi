import 'package:flutter/material.dart';

import '../data/drive_backup_service.dart';
import '../data/recipe_repository.dart';
import '../domain/backup.dart';
import 'saved_weeks_screen.dart';

String _dateTime(DateTime date) {
  final local = date.toLocal();
  return '${frenchDate(local)} à ${local.hour} h ${local.minute.toString().padLeft(2, '0')}';
}

String _count(int count, String one, String many) =>
    '$count ${count > 1 ? many : one}';

/// Sauvegarde et restauration sur Google Drive. Se ferme avec `true` quand
/// les données locales ont été remplacées.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.repository,
    required this.service,
  });
  final RecipeRepository repository;
  final DriveBackupService service;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? account;
  DateTime? lastBackup;
  bool loading = true;
  bool busy = false;
  // Un dialogue est ouvert : l'indicateur de progression est masqué.
  bool asking = false;

  @override
  void initState() {
    super.initState();
    _run('Connexion impossible', () async {
      final email = await widget.service.restoreAccount();
      if (email != null) await _connected(email);
    }).whenComplete(() {
      if (mounted) setState(() => loading = false);
    });
  }

  Future<void> _connected(String email) async {
    if (mounted) setState(() => account = email);
    final last = await widget.service.lastBackupTime();
    if (mounted) setState(() => lastBackup = last);
  }

  void _say(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  String _message(Object error, String failure) => switch (error) {
        DriveBackupException(kind: DriveError.network) =>
          'Pas de connexion. Réessaie plus tard.',
        DriveBackupException(kind: DriveError.quota) =>
          'Espace Google Drive insuffisant.',
        DriveBackupException(kind: DriveError.permissionDenied) =>
          'L\'accès au dossier de sauvegarde est nécessaire.',
        DriveBackupException(kind: DriveError.signedOut) =>
          'Session expirée. Reconnecte-toi.',
        DriveBackupException(:final statusCode) =>
          '$failure (erreur $statusCode).',
        BackupTooRecentException() =>
          'Cette sauvegarde vient d\'une version plus récente de l\'appli. Mets l\'appli à jour.',
        BackupFormatException() => 'Sauvegarde illisible.',
        _ => '$failure.',
      };

  /// Exécute une action réseau : boutons désactivés, erreur affichée.
  Future<void> _run(String failure, Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('$failure : $e');
      if (e is DriveBackupException && e.kind == DriveError.signedOut) {
        if (mounted) setState(() => account = null);
      }
      _say(_message(e, failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(String title, String text, String action) async {
    setState(() => asking = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (mounted) setState(() => asking = false);
    return confirmed ?? false;
  }

  Future<void> _signIn() => _run('Connexion impossible', () async {
        final email = await widget.service.signIn();
        if (email != null) await _connected(email);
      });

  Future<void> _signOut() => _run('Déconnexion impossible', () async {
        await widget.service.signOut();
        if (mounted) {
          setState(() {
            account = null;
            lastBackup = null;
          });
        }
      });

  Future<void> _save() => _run('Sauvegarde impossible', () async {
        final backup = await widget.repository.exportBackup();
        final last = lastBackup;
        // Nouveau téléphone : ne pas écraser la bonne copie par du vide.
        if (backup.isEmpty &&
            last != null &&
            (!mounted ||
                !await _confirm(
                  'Remplacer la sauvegarde ?',
                  'Ce téléphone ne contient aucune donnée. La sauvegarde du ${_dateTime(last)} sera remplacée par une sauvegarde vide.',
                  'Remplacer',
                ))) {
          return;
        }
        await widget.service.upload(backup);
        if (mounted) setState(() => lastBackup = backup.savedAt);
        _say('Sauvegarde effectuée.');
      });

  Future<void> _restore() => _run('Restauration impossible', () async {
        // Tout est téléchargé et vérifié avant de toucher aux données locales.
        final backup = await widget.service.download();
        if (backup == null) {
          _say('Aucune sauvegarde sur ce compte.');
          return;
        }
        if (!mounted) return;
        final skipped = backup.skippedWeeks;
        final confirmed = await _confirm(
          'Restaurer cette sauvegarde ?',
          'Sauvegarde du ${_dateTime(backup.savedAt)} : '
              '${backup.plan == null ? "aucune semaine en cours" : "une semaine en cours"}, '
              '${_count(backup.favorites.length, "favori", "favoris")}, '
              '${_count(backup.savedWeeks.length, "semaine enregistrée", "semaines enregistrées")}.'
              '${skipped == 0 ? "" : "\n${_count(skipped, "semaine illisible ignorée", "semaines illisibles ignorées")}."}'
              '\n\nLes données actuelles de ce téléphone seront remplacées.',
          'Restaurer',
        );
        if (!confirmed) return;
        await widget.repository.importBackup(backup);
        if (mounted) Navigator.pop(context, true);
      });

  @override
  Widget build(BuildContext context) {
    final email = account;
    final last = lastBackup;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sauvegarde'),
        bottom: busy && !asking && !loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      'Ta semaine en cours, tes favoris et tes semaines enregistrées sont copiés dans un dossier privé de ton Google Drive. L\'appli n\'accède à aucun autre fichier.',
                    ),
                    const SizedBox(height: 24),
                    if (email == null)
                      FilledButton.icon(
                        onPressed: busy ? null : _signIn,
                        icon: const Icon(Icons.login),
                        label: const Text('Se connecter à Google'),
                      )
                    else ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.account_circle_outlined),
                        title: Text(email),
                        subtitle: Text(
                          last == null
                              ? 'Aucune sauvegarde'
                              : 'Dernière sauvegarde : ${_dateTime(last)}',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: busy ? null : _save,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Sauvegarder maintenant'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _restore,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Restaurer'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: busy ? null : _signOut,
                        child: const Text('Se déconnecter'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
