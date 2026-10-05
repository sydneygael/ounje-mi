# Ounjé Mi — Flutter & Dart

Application **Flutter**, logique métier **Dart**, catalogue de recettes illustrées et menus hebdomadaires selon les fruits, légumes, féculents et protéines choisis. Le projet ne contient aucun serveur ou script Python.

## Fonctionnalités

- **Recettes** : 146 fiches avec photos, recherche, ingrédients, étapes et pages source.
- **Mes choix** : aliments préférés/exclus, nombre de personnes, temps maximal, végétarien et répétitions.
- **Ma semaine** : 7 déjeuners et 7 dîners ; les créneaux impossibles restent explicitement vides.
- **Courses** : ingrédients regroupés, quantités ajustées aux portions, lignes imprécises à adapter, cases à cocher et copie de la liste.
- Sauvegarde locale du dernier planning et restauration au démarrage ; export JSON par copie.

## Démarrage

Projet vérifié avec **Flutter 3.47.6 / Dart 3.13.5**. Installer le SDK Flutter stable, puis :

```bash
git clone https://github.com/sydneygael/ounje-mi.git
cd ounje-mi
flutter pub get
flutter run -d chrome
```

Les projets `android/`, `ios/`, `macos/` et `web/` sont inclus. Pour un appareil ou un émulateur natif : `flutter run`.

iOS et macOS nécessitent macOS et Xcode ; Android nécessite le SDK Android et un émulateur ou appareil. Aucune clé API n'est nécessaire. Les recettes et photos sont embarquées dans l'application.

## Base locale

Sur **Android, iOS et macOS**, `LocalRecipeRepository` utilise **SQLite via sqflite**. Le JSON embarqué est importé dans les tables `recipes`, `foods`, `recipe_foods`, `ingredient_lines` et `recipe_steps`. Les plans sont enregistrés dans `plans`. Le catalogue est mis à jour si le JSON change, sans effacer les plans.

Sur **web** et les plateformes sans cette implémentation SQLite, le catalogue reste dans les assets JSON et le dernier planning est sauvegardé avec `shared_preferences`. Il ne s'agit pas de SQLite dans le navigateur. La suppression des données du navigateur efface ce planning. Les coches de courses sont propres à la session et ne sont pas persistées.

## Choix des aliments

Un appui sur une pastille fait passer l'aliment par trois états : **préféré → exclu → neutre**. Les exclusions restent strictes quel que soit le mode. Les aliments secondaires explicitement nommés dans un ingrédient sont aussi pris en compte.

| Mode | Règle |
|---|---|
| Privilégier mes choix | Favorise les recettes contenant les aliments choisis ; les autres restent possibles. |
| Au moins un par groupe choisi | Chaque recette doit contenir au moins un aliment sélectionné de chaque groupe renseigné. |
| Limiter chaque groupe à mes choix | Dans chaque groupe renseigné, les autres aliments sont interdits. Une recette peut ne pas contenir ce groupe. Les groupes non renseignés restent libres. |

Les recettes sont sélectionnées selon leurs types de repas source ; les salades sont disponibles aux deux repas. Un même `seed` et un même catalogue produisent les mêmes repas. Le moteur ne relâche jamais les exclusions, la durée ou la limite de répétitions pour remplir la semaine.

Les fruits choisis servent à trouver les recettes qui en contiennent. L'application n'ajoute pas automatiquement de dessert. Le filtre végétarien autorise les œufs et les laitages et vérifie les aliments explicitement nommés ; la composition des marques et les ingrédients implicites restent à relire. Exclure `porc` ne supprime pas automatiquement `jambon`, `bacon`, `saucisse` ou `salami` : sélectionner aussi ces identifiants si nécessaire.

## Quantités et provenance

Les quantités numériques sont multipliées par `personnes demandées / portions source`. Seules des descriptions identiques (sans distinction majuscule/minuscule) et une même unité sont regroupées. Aucune conversion de cuillères vers grammes n'est inventée. Riz sec/cuit, saumon frais/fumé, boîtes/grammes restent séparés. Les plages et quantités imprécises sont listées à part.

Source : *Bible minceur*, Hugo Blanc, PDF fourni de **261 pages**. Import : **146 recettes, 146 photos et 1 231 lignes d'ingrédients**. Les pages imprimées et PDF sont conservées. Chaque recette porte `review_status=needs_review` : l'extraction, la classification, les variantes et les associations de photos nécessitent une relecture humaine. Les calories sont celles du livre, non recalculées et non vérifiées ; elles ne définissent pas d'objectif nutritionnel.

Une durée incluant une nuit au réfrigérateur reste inconnue et est exclue si un temps maximal est choisi. Les temps décomposés préparation/cuisson sont additionnés de façon conservatrice. Le détail des limites figure dans [docs-analysis.md](docs-analysis.md).

## Architecture

```text
lib/domain/recipe.dart           Modèles typés et décodage du catalogue
lib/domain/planner.dart          Moteur Dart, contraintes, menus et courses
lib/data/recipe_repository.dart  Interface repository, SQLite et stockage web
lib/screens/                    Interface Flutter, catalogue, choix, menus, courses
lib/main.dart                   Application et thème Material 3
assets/data/                    Catalogue JSON et rapport d'extraction
assets/photos/                  146 photos JPEG issues du PDF
test/                           Tests métier et tests de widgets
tool/validate_catalog.dart       Validation du catalogue en Dart
bin/recipe_api.dart              API HTTP locale optionnelle, en Dart
.github/workflows/flutter.yml   Analyse, tests et compilation web sur GitHub Actions
```

## Vérifications

```bash
dart format lib test tool bin
flutter analyze
flutter test
dart run tool/validate_catalog.dart
dart run tool/test_api.dart
flutter build web
```

Validation effectuée : **19 tests Flutter réussis**, **11 vérifications API Dart réussies**, analyse sans problème et **compilation web réussie**. Les compilations natives Android/iOS/macOS n’ont pas été exécutées dans cet environnement.

Les tests couvrent la semaine de 14 repas, les exclusions, les portions, les repas impossibles, les modes stricts, la reproductibilité, la sérialisation, les données et la navigation vers les menus/courses.

## API Dart optionnelle

Le moteur métier est également utilisable via une API locale Dart, sans Python. L'application Flutter fonctionne de manière autonome ; elle n'a pas besoin de cette API.

```bash
dart run bin/recipe_api.dart
curl http://127.0.0.1:8000/health
curl 'http://127.0.0.1:8000/recipes?food_ids=brocoli,quinoa&food_mode=all'
curl -X POST http://127.0.0.1:8000/plans \
  -H 'Content-Type: application/json' \
  -d '{"servings":2,"selected_foods":{"legume":["brocoli"],"feculent":["quinoa"]},"mode":"prefer"}'
```

Routes : `GET /health`, `GET /foods?group=fruit`, `GET /recipes`, `GET /recipes/{id}`, `GET /photos/{id}.jpg`, `POST /plans`, `GET /plans/{id}` et `GET /plans/{id}/shopping-list`. Filtres des recettes : `q`, `food_ids`, `food_mode=any|all`, `exclude`, `meal_type`, `max_minutes`, `vegetarian`, `limit` et `offset`. Le corps de génération accepte `days`, `servings`, `meal_types`, `selected_foods`, `excluded_foods`, `mode` (`prefer`, `requireSelected`, `onlySelected`), `max_minutes`, `vegetarian`, `max_repeats` et `seed`.

Les plans API sont enregistrés sous `local/plans/`, séparément des plans de l'application. Le serveur écoute uniquement sur `127.0.0.1`. Un port peut être passé en argument. `OUNJE_API_TOKEN` active un jeton `Authorization: Bearer ...`. Le service n'est pas un backend public multiutilisateur et ne synchronise pas les appareils.

## Droits et suites possibles

Le dépôt doit rester **privé** : les textes et photos conservent les droits du livre fourni. Aucune licence de redistribution n'est attribuée à ces données. Le PDF original n'est pas inclus.

Suites : relecture du catalogue, favoris, remplacement d'un repas, stocks, saisonnalité, desserts facultatifs, sauvegarde des courses et synchronisation entre appareils. Cette version fournit un moteur Dart local ; aucun backend distant ou déploiement public n'est configuré.
