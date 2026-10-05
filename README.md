# Ounjé Mi — recettes et menus de la semaine

API locale pour sélectionner des recettes à partir d'aliments choisis, générer une semaine de déjeuners et de dîners, consulter les photos et préparer une liste de courses adaptée au nombre de personnes.

La base initiale contient **146 recettes, 146 photos et 1 231 lignes d'ingrédients** extraites de l'édition de 261 pages de *Bible minceur*, Hugo Blanc. Chaque recette conserve ses pages source, ses ingrédients bruts, ses étapes, ses portions et sa durée. Toutes les recettes sont marquées `needs_review` : l'extraction et la classification sont automatiques.

## Lancement rapide

Python **3.11 ou plus**. L'API utilise uniquement la bibliothèque standard : aucune installation nécessaire pour consulter la base ou générer des menus.

```bash
git clone https://github.com/sydneygael/ounje-mi.git
cd ounje-mi
python3 -m app.database
python3 -m app.server
```

L'API répond sur `http://127.0.0.1:8000`. La première commande construit une base SQLite à partir de `data/recipes.json` ; le serveur la crée également au premier démarrage si elle manque. La réimportation met à jour le catalogue sans supprimer les plannings enregistrés. Les modifications doivent être faites dans le JSON source avant réimport, sinon elles seront écrasées par la réimportation.

```bash
curl http://127.0.0.1:8000/health
curl 'http://127.0.0.1:8000/foods?group=legume'
curl 'http://127.0.0.1:8000/recipes?food_ids=brocoli,quinoa&food_mode=all'
curl http://127.0.0.1:8000/recipes/bm-176
```

Les identifiants utilisables sont retournés par `/foods`. Exemples : `pomme`, `banane`, `brocoli`, `epinard`, `riz`, `quinoa`, `patate-douce`, `poulet`, `saumon`. Le catalogue comprend aussi légumineuses, laitages, boissons végétales, noix et graines, matières grasses et condiments. L'avocat est classé comme légume pour l'usage culinaire ; patate douce et pomme de terre comme féculents.

## Générer les menus de la semaine

```bash
curl -X POST http://127.0.0.1:8000/plans \
  -H 'Content-Type: application/json' \
  -d '{
    "days": 7,
    "servings": 2,
    "meal_types": ["dejeuner", "diner"],
    "selected_foods": {
      "fruit": ["pomme", "citron"],
      "legume": ["brocoli", "epinard", "courgette"],
      "feculent": ["riz", "quinoa", "patate-douce"]
    },
    "selection_mode": "prefer",
    "excluded_foods": ["porc", "jambon", "bacon", "saucisse", "salami"],
    "max_minutes": 45,
    "max_repeats": 1,
    "vegetarian": false,
    "seed": 42
  }'
```

Les choix de fruits servent aussi à trouver les recettes salées contenant des fruits. Le planning n'ajoute pas automatiquement un fruit en dessert et ne modifie pas la recette d'origine.

| Mode | Comportement |
|---|---|
| `prefer` | Les recettes contenant les aliments choisis sont mieux classées ; les autres restent disponibles. |
| `require_selected` | Chaque recette doit contenir au moins un aliment choisi de **chaque groupe renseigné**. Choisir fruit + légume + féculent peut fortement restreindre le résultat. |
| `only_selected` | Pour chaque groupe renseigné, aucun autre aliment du même groupe n'est permis. Les groupes non renseignés restent libres ; une recette peut ne pas contenir le groupe sélectionné. |

Les exclusions, la durée maximale, le filtre végétarien et le nombre maximal de répétitions s'appliquent dans tous les modes. Aucun n'est assoupli automatiquement. Le planning par défaut comprend 7 jours, 2 personnes, déjeuners et dîners et au plus une occurrence de chaque recette.

La réponse contient un identifiant de planning, les repas, les URL des photos, les aliments choisis retrouvés et la liste de courses. `complete=false` et `unfilled_slots` indiquent les créneaux impossibles à remplir. Un résultat partiel est enregistré comme tel. Le même `seed` et le même catalogue produisent les mêmes repas, avec un nouvel identifiant de planning.

```bash
curl http://127.0.0.1:8000/plans/IDENTIFIANT
curl http://127.0.0.1:8000/plans/IDENTIFIANT/shopping-list
```

Les recettes « Déjeuner » sont proposées au déjeuner, les recettes « Dîner » au dîner et les salades aux deux. Boissons, petits-déjeuners, vinaigrettes et collations ne remplacent pas ces repas. Les variantes sont consultatives et ne sont jamais substituées silencieusement aux ingrédients.

## Liste de courses et portions

Les quantités numériques sont multipliées par `personnes demandées / portions de la recette`. Seules les lignes ayant la même description normalisée et la même unité sont fusionnées. Riz cuit et riz sec, saumon frais et saumon fumé ou boîtes et grammes restent séparés. Aucune conversion cuillère-vers-grammes n'est inventée.

Les quantités imprécises, les plages et les ingrédients non chiffrés figurent dans `manual_items`, avec leur texte source et le multiplicateur de portions. La liste est une aide à préparer les achats ; elle ne calcule pas le nombre exact de paquets ni les stocks déjà disponibles.

## API

| Méthode | Route | Usage |
|---|---|---|
| GET | `/health` | État de l'API et nombre de recettes |
| GET | `/foods?group=fruit` | Identifiants d'aliments, groupes |
| GET | `/recipes` | Recherche paginée |
| GET | `/recipes/{id}` | Recette complète, étapes et provenance |
| GET | `/photos/{id}.jpg` | Photo extraite du PDF |
| POST | `/plans` | Génération et enregistrement d'un planning |
| GET | `/plans/{id}` | Relecture d'un planning |
| GET | `/plans/{id}/shopping-list` | Liste de courses enregistrée |
| GET | `/openapi.json` | Contrat OpenAPI 3.1 |

Filtres `/recipes` : `food_ids` séparés par virgules, `food_mode=any|all`, `exclude` (identifiants), `category`, `meal_type`, `max_minutes`, `q` (titre), `vegetarian=true|false`, `limit` (1–200, défaut 50), `offset` (défaut 0). Les identifiants d'aliments inconnus sont rejetés. Les corps invalides renvoient HTTP 400, les ressources inconnues 404, les créations de planning 201. Les filtres portent sur le texte des ingrédients, y compris les aliments secondaires explicitement nommés.

## Structure et données

```text
app/                 API, sélection, SQLite et taxonomie
scripts/import_pdf.py Importeur propre à cette édition
data/recipes.json     Catalogue source exploitable sans SQLite
data/photos/          Photos JPEG extraites, une par recette
data/import-report.json Compteurs et empreinte SHA-256 du PDF
docs/analysis.md      Analyse du PDF et limites
docs/openapi.json     Contrat de l'API
tests/                Tests de données, planning et HTTP
```

SQLite contient les tables `recipes`, `foods`, `recipe_foods`, `ingredient_lines`, `steps`, `photos`, `meal_plans` et `planned_meals`. Les clés étrangères assurent les liens ; les photos restent sur disque. Un JSON de la recette complète conserve les champs source en complément des tables normalisées. Les étapes utilisent une position unique indépendante de la numérotation parfois répétée du livre.

Les calories sont conservées avec `nutrition_source=book_unverified`. L'application n'applique pas les recommandations nutritionnelles du livre, ne définit pas d'objectif calorique et ne garantit aucun résultat de perte de poids. Le filtre végétarien est déduit des ingrédients nommés ; la composition des marques et les ingrédients implicites restent à vérifier. Les champs `allergens` sont des indications automatiques, pas une certification d'absence d'allergènes ; il n'existe pas de filtre « sans allergène » garanti.

## Réimporter le PDF

Le PDF n'est pas commité. Conserver une copie locale de cette édition puis :

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-import.txt
python scripts/import_pdf.py '/chemin/Bible-minceur.pdf'
python -m app.database
```

L'importeur utilise la table des matières, réunit les pages d'une recette, extrait les blocs d'ingrédients et d'étapes et sélectionne la plus grande photographie de la recette. Il attend cette édition de 261 pages ; il ne constitue pas un importeur générique. Les métadonnées de photos conservent la page et l'empreinte de chaque JPEG. Les variantes sont extraites au mieux des blocs identifiables et nécessitent une relecture.

## Tests

```bash
python3 -m unittest discover -s tests -v
```

La suite vérifie le catalogue et les empreintes des 146 photos, les recettes sur deux pages, les durées combinées, les portions, la reproductibilité, les exclusions, les menus impossibles, la persistance, l'API et l'authentification optionnelle.

## Configuration et Docker

Variables : `MEAL_DATA_DIR` (catalogue et photos), `MEAL_DB_PATH` (base), `MEAL_API_TOKEN` (jeton optionnel, accès avec `Authorization: Bearer ...`). Les chemins par défaut sont dans `data/`. Le serveur écoute uniquement sur l'interface locale par défaut. C'est un service pour usage personnel ; il ne comprend ni comptes utilisateurs ni interface web ni authentification multiutilisateur.

```bash
docker build -t meal-planner .
docker run --rm -p 127.0.0.1:8000:8000 \
  -v meal-planner-state:/state meal-planner
```

La base des plannings est persistée dans le volume `/state`. Pour un accès distant, ajouter HTTPS, authentification et sauvegardes. La recette JSON et les photos doivent être sauvegardées avec la base. La construction et l'exécution Docker nécessitent Docker installé.

## Droits sur les données et prochaines étapes

**Ce dépôt doit rester privé.** Les textes et photos extraits restent des contenus du livre fourni, avec leurs droits d'origine ; aucune licence de redistribution ne leur est attribuée. Le code et les données sont distingués pour faciliter une future migration vers des recettes et photos autorisées. La publication d'un catalogue destiné à des tiers nécessite des droits adaptés.

Suite proposée : relire les extractions, corriger les catégories et compositions ambiguës, ajouter favoris et stocks, remplacement d'un repas, desserts facultatifs, saisonnalité, puis interface web. Une migration vers Java/Spring et PostgreSQL est possible à partir du JSON, du schéma et du contrat API si ce stack est souhaité.
