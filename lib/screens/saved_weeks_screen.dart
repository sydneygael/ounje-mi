import 'package:flutter/material.dart';

import '../data/recipe_repository.dart';
import '../domain/planner.dart';
import '../domain/recipe.dart';

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String frenchDate(DateTime date, {bool year = false}) {
  final local = date.toLocal();
  return '${local.day == 1 ? "1er" : local.day} ${_months[local.month - 1]}${year ? " ${local.year}" : ""}';
}

/// Demande un nom de semaine ; renvoie `null` si l'utilisateur annule.
Future<String?> askWeekName(
  BuildContext context, {
  required String title,
  required String initial,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _WeekNameDialog(title: title, initial: initial),
    );

class _WeekNameDialog extends StatefulWidget {
  const _WeekNameDialog({required this.title, required this.initial});
  final String title;
  final String initial;
  @override
  State<_WeekNameDialog> createState() => _WeekNameDialogState();
}

class _WeekNameDialogState extends State<_WeekNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Nom de la semaine'),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      );
}

enum _WeekAction { reuse, rename, delete }

/// Liste des semaines nommées. Se ferme avec la semaine à réutiliser.
class SavedWeeksScreen extends StatefulWidget {
  const SavedWeeksScreen({
    super.key,
    required this.repository,
    required this.recipes,
  });
  final RecipeRepository repository;
  final List<Recipe> recipes;
  @override
  State<SavedWeeksScreen> createState() => _SavedWeeksScreenState();
}

class _SavedWeeksScreenState extends State<SavedWeeksScreen> {
  List<SavedWeek> weeks = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.repository.loadSavedWeeks();
      if (!mounted) return;
      setState(() {
        weeks = loaded;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Chargement impossible : $e';
          loading = false;
        });
      }
    }
  }

  Future<void> _change(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Modification impossible : $e')),
        );
      }
    }
    await _load();
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
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
      ) ??
      false;

  Future<void> _run(_WeekAction action, SavedWeek week) async {
    switch (action) {
      case _WeekAction.reuse:
        if (await _confirm(
              'Réutiliser cette semaine ?',
              'La semaine actuelle sera remplacée par « ${week.name} ».',
              'Réutiliser',
            ) &&
            mounted) {
          Navigator.pop(context, week);
        }
      case _WeekAction.rename:
        final name = await askWeekName(
          context,
          title: 'Renommer la semaine',
          initial: week.name,
        );
        if (name != null && name != week.name) {
          await _change(() => widget.repository.renameWeek(week.id, name));
        }
      case _WeekAction.delete:
        if (await _confirm(
          'Supprimer cette semaine ?',
          '« ${week.name} » sera supprimée définitivement.',
          'Supprimer',
        )) {
          await _change(() => widget.repository.deleteWeek(week.id));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = {for (final r in widget.recipes) r.id: r};
    return Scaffold(
      appBar: AppBar(title: const Text('Mes semaines')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!, textAlign: TextAlign.center),
                  ),
                )
              : weeks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucune semaine enregistrée. Enregistre une semaine depuis « Ma semaine » pour la retrouver ici.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: weeks.map((week) {
                            final plan = week.plan;
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: ExpansionTile(
                                key: PageStorageKey<String>('week-${week.id}'),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(week.name),
                                subtitle: Text(
                                  '${frenchDate(week.savedAt, year: true)} · ${plan.meals.length}/${plan.options.days * plan.options.mealTypes.length} repas · ${plan.options.servings} personnes',
                                ),
                                trailing: PopupMenuButton<_WeekAction>(
                                  tooltip: 'Actions',
                                  onSelected: (action) => _run(action, week),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: _WeekAction.reuse,
                                      child: Text('Réutiliser'),
                                    ),
                                    PopupMenuItem(
                                      value: _WeekAction.rename,
                                      child: Text('Renommer'),
                                    ),
                                    PopupMenuItem(
                                      value: _WeekAction.delete,
                                      child: Text('Supprimer'),
                                    ),
                                  ],
                                ),
                                children: plan.meals.map((meal) {
                                  final recipe = index[meal.recipeId];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      recipe == null || recipe.servings == null
                                          ? 'Recette retirée'
                                          : recipe.title,
                                    ),
                                    subtitle: Text(
                                      'Jour ${meal.day} · ${mealLabels[meal.mealType] ?? meal.mealType}',
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
    );
  }
}
