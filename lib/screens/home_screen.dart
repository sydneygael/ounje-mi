import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/recipe_repository.dart';
import '../domain/planner.dart';
import '../domain/recipe.dart';
import 'recipe_screen.dart';
import 'saved_weeks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});
  final RecipeRepository repository;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final planner = const WeeklyPlanner();
  List<Recipe> recipes = [];
  MealPlan? plan;
  String? error;
  bool loading = true;
  bool saving = false;
  int tab = 0;
  String search = '';
  int servings = 2;
  int? maxMinutes;
  int maxRepeats = 1;
  bool vegetarian = false;
  int seed = 0;
  SelectionMode mode = SelectionMode.prefer;
  final selected = <String, Set<String>>{};
  final excluded = <String>{};
  final checked = <String>{};
  final favorites = <String>{};
  bool favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.repository.loadRecipes();
      final saved = await widget.repository.loadPlan();
      final savedFavorites = await widget.repository.loadFavorites();
      if (!mounted) return;
      setState(() {
        recipes = loaded;
        // Le catalogue a pu être réimporté depuis la sauvegarde du planning.
        plan = saved == null ? null : planner.reconcile(saved, loaded);
        loading = false;
        favorites
          ..clear()
          ..addAll(savedFavorites);
        if (saved != null) _applyOptions(saved.options);
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

  /// Recopie les options d'un planning dans le formulaire « Mes choix ».
  void _applyOptions(PlanOptions saved) {
    servings = saved.servings;
    maxMinutes = saved.maxMinutes;
    maxRepeats = saved.maxRepeats;
    vegetarian = saved.vegetarian;
    seed = saved.seed + 1;
    mode = saved.mode;
    selected.clear();
    selected.addAll(
      saved.selectedFoods.map((k, v) => MapEntry(k, Set<String>.from(v))),
    );
    excluded.clear();
    excluded.addAll(saved.excludedFoods);
  }

  String _newId(DateTime now) =>
      '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';

  Future<void> _saveWeek(MealPlan current) async {
    final name = await askWeekName(
      context,
      title: 'Enregistrer cette semaine',
      initial: 'Semaine du ${frenchDate(current.createdAt)}',
    );
    if (name == null) return;
    try {
      final now = DateTime.now().toUtc();
      await widget.repository.saveWeek(
        SavedWeek(id: _newId(now), name: name, savedAt: now, plan: current),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('« $name » enregistrée dans Mes semaines.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $e')),
        );
      }
    }
  }

  Future<void> _openWeeks() async {
    final week = await Navigator.of(context).push(
      MaterialPageRoute<SavedWeek>(
        builder: (context) => SavedWeeksScreen(
          repository: widget.repository,
          recipes: recipes,
        ),
      ),
    );
    if (week == null) return;
    try {
      final now = DateTime.now().toUtc();
      // Copie sous un nouvel identifiant : le modèle reste intact.
      final reused = planner.reconcile(
        MealPlan(
          id: _newId(now),
          options: week.plan.options,
          meals: week.plan.meals,
          unfilledSlots: week.plan.unfilledSlots,
          createdAt: now,
        ),
        recipes,
      );
      await widget.repository.savePlan(reused);
      if (!mounted) return;
      setState(() {
        plan = reused;
        checked.clear();
        _applyOptions(reused.options);
        tab = 2;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Réutilisation impossible : $e')),
        );
      }
    }
  }

  PlanOptions get options => PlanOptions(
        servings: servings,
        maxMinutes: maxMinutes,
        maxRepeats: maxRepeats,
        vegetarian: vegetarian,
        seed: seed,
        mode: mode,
        selectedFoods: selected.map((k, v) => MapEntry(k, Set<String>.from(v))),
        excludedFoods: Set<String>.from(excluded),
        favoriteRecipes: Set<String>.from(favorites),
      );

  /// Bascule un favori et renvoie son état réel après la sauvegarde.
  Future<bool> _toggleFavorite(String recipeId) async {
    final value = !favorites.contains(recipeId);
    setState(
      () => value ? favorites.add(recipeId) : favorites.remove(recipeId),
    );
    try {
      await widget.repository.setFavorite(recipeId, value);
      return value;
    } catch (e) {
      if (mounted) {
        setState(
          () => value ? favorites.remove(recipeId) : favorites.add(recipeId),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Favori non enregistré : $e')),
        );
      }
      return !value;
    }
  }

  Future<void> _generate() async {
    setState(() => saving = true);
    try {
      final generated = planner.generate(recipes, options);
      await widget.repository.savePlan(generated);
      if (!mounted) return;
      setState(() {
        plan = generated;
        checked.clear();
        tab = 2;
        seed++;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Génération ou sauvegarde impossible : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _open(Recipe recipe, {int? portions}) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RecipeScreen(
            recipe: recipe,
            initialServings: portions,
            favorite: favorites.contains(recipe.id),
            onToggleFavorite: () => _toggleFavorite(recipe.id),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Ounjé Mi'),
          actions: [
            IconButton(
              tooltip: 'À propos des recettes',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Des recettes pour ta semaine'),
                  content: const Text(
                    '146 recettes et photos issues du PDF fourni. Extraction automatique à relire. Les exclusions portent sur les ingrédients identifiables, pas sur les traces ou les compositions implicites. Les calories proviennent du livre.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fermer'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: switch (tab) {
                        0 => _catalog(),
                        1 => _choices(),
                        2 => _week(),
                        _ => _shopping(),
                      },
                    ),
                  ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.restaurant_menu),
              label: 'Recettes',
            ),
            NavigationDestination(icon: Icon(Icons.tune), label: 'Mes choix'),
            NavigationDestination(
              icon: Icon(Icons.calendar_month),
              label: 'Ma semaine',
            ),
            NavigationDestination(
              icon: Icon(Icons.shopping_basket_outlined),
              label: 'Courses',
            ),
          ],
        ),
      );

  Widget _catalog() {
    final preferred = selected.values.expand((s) => s).toSet();
    final shown = recipes
        .where(
          (r) =>
              r.title.toLowerCase().contains(search.toLowerCase()) &&
              // Le filtre favoris ignore « Mes choix » pour ne rien cacher.
              (favoritesOnly
                  ? favorites.contains(r.id)
                  : planner.matches(r, options)),
        )
        .toList();
    shown.sort((a, b) {
      final score = b.foodIds
          .intersection(preferred)
          .length
          .compareTo(a.foodIds.intersection(preferred).length);
      return score != 0 ? score : a.title.compareTo(b.title);
    });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Chercher une recette',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => search = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  favoritesOnly
                      ? shown.length == 1
                          ? '1 favori'
                          : '${shown.length} favoris'
                      : '${shown.length} recettes · selon mes choix',
                ),
              ),
              FilterChip(
                label: const Text('Favoris'),
                selected: favoritesOnly,
                onSelected: (v) => setState(() => favoritesOnly = v),
              ),
              TextButton(
                onPressed: () => setState(() => tab = 1),
                child: const Text('Modifier'),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      !favoritesOnly
                          ? 'Aucune recette ne correspond à ces choix.'
                          : favorites.isEmpty
                              ? 'Aucun favori pour l\'instant. Touche le cœur d\'une recette pour l\'ajouter.'
                              : 'Aucun favori ne correspond à cette recherche.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 850
                        ? 3
                        : constraints.maxWidth >= 550
                            ? 2
                            : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 290,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final recipe = shown[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _open(recipe),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    Image.asset(
                                      recipe.photoAsset,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => const SizedBox(
                                        height: 180,
                                        child: Center(
                                          child:
                                              Icon(Icons.restaurant, size: 50),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton.filledTonal(
                                        tooltip: favorites.contains(recipe.id)
                                            ? 'Retirer des favoris'
                                            : 'Ajouter aux favoris',
                                        icon: Icon(
                                          favorites.contains(recipe.id)
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                        ),
                                        onPressed: () =>
                                            _toggleFavorite(recipe.id),
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        recipe.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${recipe.totalMinutes == null ? "Durée inconnue" : "${recipe.totalMinutes} min"} · ${recipe.servings ?? "?"} personnes',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _choices() {
    final foods = <String, Food>{};
    for (final recipe in recipes) {
      for (final f in recipe.ingredients.expand((i) => i.foods)) {
        foods[f.id] = f;
      }
    }
    return ListView(
      key: const PageStorageKey<String>('choices'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Compose ta semaine',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Touche un aliment : préféré → exclu → aucun choix. Les exclusions sont toujours respectées.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                initialValue: servings,
                decoration: const InputDecoration(labelText: 'Personnes'),
                items: List.generate(
                  20,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                ),
                onChanged: (v) => setState(() => servings = v!),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                initialValue: maxMinutes ?? 0,
                decoration: const InputDecoration(labelText: 'Temps maximum'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Sans limite')),
                  DropdownMenuItem(value: 15, child: Text('15 minutes')),
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  DropdownMenuItem(value: 45, child: Text('45 minutes')),
                  DropdownMenuItem(value: 60, child: Text('60 minutes')),
                  DropdownMenuItem(value: 90, child: Text('90 minutes')),
                ],
                onChanged: (v) =>
                    setState(() => maxMinutes = v == 0 ? null : v),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                initialValue: maxRepeats,
                decoration: const InputDecoration(
                  labelText: 'Maximum par recette',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 repas')),
                  DropdownMenuItem(value: 2, child: Text('2 repas')),
                  DropdownMenuItem(value: 3, child: Text('3 repas')),
                ],
                onChanged: (v) => setState(() => maxRepeats = v!),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Végétarien'),
          subtitle:
              const Text('Œufs et laitages autorisés ; ingrédients nommés'),
          value: vegetarian,
          onChanged: (v) => setState(() => vegetarian = v),
        ),
        DropdownButtonFormField<SelectionMode>(
          initialValue: mode,
          decoration: const InputDecoration(
            labelText: 'Comment utiliser mes aliments ?',
          ),
          items: const [
            DropdownMenuItem(
              value: SelectionMode.prefer,
              child: Text('Privilégier mes choix'),
            ),
            DropdownMenuItem(
              value: SelectionMode.requireSelected,
              child: Text('Au moins un par groupe choisi'),
            ),
            DropdownMenuItem(
              value: SelectionMode.onlySelected,
              child: Text('Limiter chaque groupe à mes choix'),
            ),
          ],
          onChanged: (v) => setState(() => mode = v!),
        ),
        const SizedBox(height: 8),
        Text(switch (mode) {
          SelectionMode.prefer =>
            'Les recettes contenant tes choix sont privilégiées. Les autres restent disponibles.',
          SelectionMode.requireSelected =>
            'Chaque recette doit contenir au moins un aliment de chaque groupe choisi.',
          SelectionMode.onlySelected =>
            'Dans chaque groupe choisi, les autres aliments sont interdits. Les groupes non choisis restent libres.',
        }),
        const SizedBox(height: 16),
        ...groupLabels.entries.map((entry) {
          final list = foods.values.where((f) => f.group == entry.key).toList()
            ..sort((a, b) => a.label.compareTo(b.label));
          return ExpansionTile(
            key: PageStorageKey<String>('group-${entry.key}'),
            tilePadding: EdgeInsets.zero,
            title: Text(entry.value),
            initiallyExpanded: [
              'fruit',
              'legume',
              'feculent',
            ].contains(entry.key),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: list.map((food) {
                    final preferred =
                        selected[food.group]?.contains(food.id) ?? false;
                    final banned = excluded.contains(food.id);
                    return ActionChip(
                      label: Text(food.label),
                      avatar: preferred
                          ? const Icon(Icons.check, size: 18)
                          : banned
                              ? const Icon(Icons.block, size: 18)
                              : null,
                      backgroundColor: banned
                          ? Theme.of(context).colorScheme.errorContainer
                          : preferred
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                      onPressed: () => setState(() {
                        final group = selected.putIfAbsent(
                          food.group,
                          () => <String>{},
                        );
                        if (preferred) {
                          group.remove(food.id);
                          excluded.add(food.id);
                        } else if (banned) {
                          excluded.remove(food.id);
                        } else {
                          group.add(food.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : _generate,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(saving ? 'Préparation…' : 'Proposer mes 14 repas'),
        ),
        TextButton(
          onPressed: () => setState(() {
            selected.clear();
            excluded.clear();
            vegetarian = false;
            maxMinutes = null;
            mode = SelectionMode.prefer;
          }),
          child: const Text('Réinitialiser les choix'),
        ),
      ],
    );
  }

  Widget _week() {
    final saved = plan;
    if (saved == null) {
      return _empty(
        'Ta semaine commence ici',
        'Choisis tes aliments puis génère tes repas.',
        () => setState(() => tab = 1),
        'Choisir mes aliments',
        secondary: TextButton.icon(
          onPressed: _openWeeks,
          icon: const Icon(Icons.bookmarks_outlined),
          label: const Text('Mes semaines'),
        ),
      );
    }
    final index = {for (final r in recipes) r.id: r};
    return ListView(
      key: ValueKey<String>('week-${saved.id}'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Ma semaine', style: Theme.of(context).textTheme.headlineMedium),
        Text(
          '${saved.meals.length}/${saved.options.days * saved.options.mealTypes.length} repas · ${saved.options.servings} personnes',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: saving ? null : _generate,
              icon: const Icon(Icons.refresh),
              label: const Text('Nouvelle proposition'),
            ),
            TextButton.icon(
              onPressed: () => setState(() => tab = 3),
              icon: const Icon(Icons.shopping_basket_outlined),
              label: const Text('Voir les courses'),
            ),
            TextButton.icon(
              onPressed: () => _saveWeek(saved),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Enregistrer cette semaine'),
            ),
            TextButton.icon(
              onPressed: _openWeeks,
              icon: const Icon(Icons.bookmarks_outlined),
              label: const Text('Mes semaines'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent('  ')
                        .convert(saved.toJson()),
                  ),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Planning copié au format JSON.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copier le planning'),
            ),
          ],
        ),
        if (!saved.complete)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Certains créneaux restent vides : modifie les choix ou augmente les répétitions.',
            ),
          ),
        ...List.generate(saved.options.days, (i) {
          final day = i + 1;
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jour $day',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...saved.options.mealTypes.map((type) {
                  final meals = saved.meals.where(
                    (m) => m.day == day && m.mealType == type,
                  );
                  final meal = meals.isEmpty ? null : meals.first;
                  final recipe = meal == null ? null : index[meal.recipeId];
                  if (recipe == null) {
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_busy),
                        title: Text(mealLabels[type] ?? type),
                        subtitle: Text(
                          saved.unfilledSlots
                                  .where(
                                    (s) =>
                                        s['day'] == day &&
                                        s['meal_type'] == type,
                                  )
                                  .map((s) => s['reason'] as String?)
                                  .firstOrNull ??
                              'Aucune recette disponible pour ce créneau.',
                        ),
                      ),
                    );
                  }
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          recipe.photoAsset,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) =>
                              const Icon(Icons.restaurant),
                        ),
                      ),
                      title: Text(recipe.title),
                      subtitle: Text(
                        '${mealLabels[type]} · ${meal!.servings} personnes',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(recipe, portions: meal.servings),
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _shopping() {
    final saved = plan;
    if (saved == null) {
      return _empty(
        'La liste se prépare avec tes menus',
        'Génère une semaine pour regrouper les ingrédients.',
        () => setState(() => tab = 1),
        'Préparer ma semaine',
      );
    }
    final list = planner.shoppingList(saved, recipes);
    return ListView(
      key: ValueKey<String>('shopping-${saved.id}'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Mes courses', style: Theme.of(context).textTheme.headlineMedium),
        const Text(
          'Quantités ajustées aux personnes. Unités et préparations différentes restent séparées.',
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () async {
            final text = [
              ...list.items.map(
                (i) =>
                    '${i.displayQuantity} ${i.unit == "piece" ? "" : i.unit} ${i.description}',
              ),
              if (list.manualItems.isNotEmpty) '\nÀ ajuster manuellement :',
              ...list.manualItems,
            ].join('\n');
            await Clipboard.setData(ClipboardData(text: text));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Liste de courses copiée.')),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copier ma liste'),
        ),
        ...groupLabels.entries
            .where((entry) => list.items.any((i) => i.group == entry.key))
            .map(
              (entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    entry.value,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...list.items.where((i) => i.group == entry.key).map((item) {
                    final key = '${item.description}\u0000${item.unit}';
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked.contains(key),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          checked.add(key);
                        } else {
                          checked.remove(key);
                        }
                      }),
                      title: Text(item.description),
                      subtitle: Text(
                        '${item.displayQuantity} ${item.unit == "piece" ? "unité(s) source" : item.unit}',
                      ),
                    );
                  }),
                ],
              ),
            ),
        if (list.manualItems.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'À ajuster manuellement',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...list.manualItems.map(
            (item) =>
                ListTile(contentPadding: EdgeInsets.zero, title: Text(item)),
          ),
        ],
      ],
    );
  }

  Widget _empty(
    String title,
    String text,
    VoidCallback action,
    String label, {
    Widget? secondary,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.eco_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: action, child: Text(label)),
              if (secondary != null) ...[const SizedBox(height: 8), secondary],
            ],
          ),
        ),
      );
}
