import 'package:flutter/material.dart';

import '../domain/recipe.dart';

const _qualityNotes = {
  'source_step_numbering': 'numérotation des étapes du livre',
  'summed_time_components': 'durées de préparation et de cuisson additionnées',
  'unquantified_overnight_wait': 'une nuit de repos est nécessaire',
};

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({
    super.key,
    required this.recipe,
    this.initialServings,
    this.favorite = false,
    this.onToggleFavorite,
  });
  final Recipe recipe;
  final int? initialServings;
  final bool favorite;

  /// Bascule le favori et renvoie son état réel après la sauvegarde.
  final Future<bool> Function()? onToggleFavorite;
  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  late int servings;
  late bool favorite;
  @override
  void initState() {
    super.initState();
    servings = widget.initialServings ?? widget.recipe.servings ?? 2;
    favorite = widget.favorite;
  }

  Future<void> _toggleFavorite() async {
    setState(() => favorite = !favorite);
    final actual = await widget.onToggleFavorite!();
    if (mounted && actual != favorite) setState(() => favorite = actual);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final scale = servings / (r.servings ?? servings);
    return Scaffold(
      appBar: AppBar(
        title: Text(r.title),
        actions: [
          if (widget.onToggleFavorite != null)
            IconButton(
              tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
              icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
              onPressed: _toggleFavorite,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  r.photoAsset,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const SizedBox(
                    height: 160,
                    child: Icon(Icons.restaurant, size: 60),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(r.title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '${r.totalMinutes == null ? "Durée totale inconnue" : "${r.totalMinutes} min"} · ${r.servings ?? "?"} portions source',
              ),
              if (r.kcalPerServing != null)
                Text(
                  '${r.kcalPerServing} kcal / portion source · valeur du livre non vérifiée',
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Personnes'),
                  IconButton(
                    onPressed:
                        servings > 1 ? () => setState(() => servings--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$servings'),
                  IconButton(
                    onPressed:
                        servings < 20 ? () => setState(() => servings++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Ingrédients',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ...r.ingredients.map(
                (i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.circle, size: 8),
                  title: Text(i.raw),
                  subtitle: scale == 1
                      ? null
                      : Text(
                          i.quantity == null
                              ? 'Quantité à adapter ×${scale.toStringAsFixed(2)}'
                              : '${(i.quantity! * scale).toStringAsFixed(2)} ${i.unit == "piece" ? "" : i.unit ?? ""} ${i.description}',
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Préparation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ...List.generate(r.steps.length, (index) {
                final s = r.steps[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(s.text),
                  subtitle:
                      s.component == 'principal' ? null : Text(s.component),
                );
              }),
              if ((r.source['variants'] as List).isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Variantes du livre',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...(r.source['variants'] as List).map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(v as String),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Source : Bible minceur, Hugo Blanc · pages PDF ${r.pdfPages.join(", ")}.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Extraction automatique à relire. Les portions sont ajustées sans modifier les temps de cuisson.',
              ),
              if (r.qualityFlags.isNotEmpty)
                Text(
                    'À vérifier : ${r.qualityFlags.map((flag) => _qualityNotes[flag] ?? "texte source à relire").join(" ; ")}.'),
            ],
          ),
        ),
      ),
    );
  }
}
