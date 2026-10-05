# Favoris et semaines enregistrées — design

Date : 5 octobre 2026. Statut : design validé, non implémenté.

## Objectif

- **Favoris** : marquer des recettes ; le moteur les privilégie sans relâcher aucune contrainte.
- **Semaines enregistrées** : donner un nom à une semaine réussie et la réutiliser comme modèle.

## Décisions

| Sujet | Décision |
|---|---|
| Effet d'un favori | Bonus de score dans le moteur ; les autres recettes restent possibles. |
| Contenu de la liste des semaines | Seulement les semaines nommées explicitement. Les essais non enregistrés sont remplacés par le suivant. |
| Stockage | Deux tables SQLite dédiées (`favorites`, `saved_weeks`), base en version 2 ; deux clés `shared_preferences` sur le web. |
| Plafond de favoris par semaine | Aucun pour l'instant ; à ajuster à l'usage. |
| Filtre « Favoris » du catalogue | Affiche tous les favoris, sans appliquer « Mes choix ». |

Approches de stockage écartées : réutiliser `plans` avec une colonne `name` (oblige à marquer la semaine courante, car `loadPlan` lit la ligne la plus récente) ; tout mettre dans `shared_preferences` (abandonne SQLite sur mobile pour ces données).

## 1. Modèle de données et repository

### Domaine (`lib/domain/planner.dart`)

- Nouvelle classe `SavedWeek` : `id`, `name`, `savedAt`, `plan` (`MealPlan`), avec `toJson`/`fromJson`.
- `PlanOptions.favoriteRecipes` : `Set<String>`, vide par défaut, sérialisé sous `favorite_recipes`. `fromJson` accepte l'absence de la clé pour relire les plannings existants. Les favoris passent par les options pour préserver la règle : mêmes options et même `seed` donnent les mêmes repas.

### Repository (`lib/data/recipe_repository.dart`)

| Méthode | Rôle |
|---|---|
| `loadFavorites()` | Identifiants des recettes favorites |
| `setFavorite(id, value)` | Ajoute ou retire un favori |
| `loadSavedWeeks()` | Semaines nommées, la plus récente d'abord |
| `saveWeek(week)` | Enregistre une semaine nommée |
| `renameWeek(id, name)` | Renomme |
| `deleteWeek(id)` | Supprime |

### SQLite, version 2

```sql
CREATE TABLE favorites (recipe_id TEXT PRIMARY KEY);
CREATE TABLE saved_weeks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  saved_at TEXT NOT NULL,
  payload TEXT NOT NULL
);
```

- `favorites` n'a **pas** de clé étrangère vers `recipes` : `loadRecipes` vide et réimporte cette table quand le catalogue change, et un `ON DELETE CASCADE` effacerait les favoris.
- Les deux tables sont créées dans `onCreate` et dans `onUpgrade`.
- `savePlan` supprime les autres lignes de `plans` dans la même transaction : la table ne contient plus que la semaine courante.
- À la migration, les lignes de `plans` autres que la plus récente sont purgées. Elles ne sont visibles nulle part aujourd'hui.

### Web

- `ounje_mi_favorites` : liste de chaînes.
- `ounje_mi_saved_weeks` : liste JSON.

## 2. Bonus de score dans le moteur

Formule dans `WeeklyPlanner.generate` :

```
score = aliments préférés présents × 10
      + 2 si la recette est favorite
      − utilisations déjà faites × 3
```

Le bonus vaut 2 pour deux raisons :

- **inférieur à 10** : un aliment préféré pèse toujours plus qu'un favori ;
- **inférieur à 3** : un favori déjà servi (−1) passe derrière une recette pas encore utilisée (0), donc il ne revient pas deux fois avant les autres.

Inchangé : `matches` (un favori exclu, trop long ou non végétarien reste écarté), le départage par `seed`, et le résultat sans favoris pour un même `seed`.

Un favori absent du catalogue est ignoré sans erreur, contrairement aux aliments inconnus qui lèvent une `ArgumentError`.

Conséquence connue : le moteur remplit les créneaux dans l'ordre. À score d'aliments égal, les favoris sont placés en début de semaine ; avec plus de favoris éligibles que de créneaux, la semaine n'est faite que de favoris. Variante possible plus tard : plafonner le bonus aux N premiers favoris placés.

## 3. Interface

### Favoris

- **Catalogue** : cœur en haut à droite de chaque photo.
- **Fiche recette** : cœur dans la barre de titre. `RecipeScreen` reçoit l'état initial et un rappel `onFavoriteChanged`.
- L'ensemble `favorites` vit dans `HomeScreen`, chargé dans `_load` et transmis au moteur par le getter `options`.
- **Filtre** : pastille « Favoris » sur la ligne du compteur. Activée, elle affiche tous les favoris sans appliquer « Mes choix » ; seule la recherche par titre reste active.

### Enregistrer une semaine

Bouton « Enregistrer cette semaine » dans « Ma semaine ». Dialogue avec un nom prérempli (« Semaine du 5 octobre »), obligatoire, 40 caractères au plus. Les doublons de nom sont permis ; la date les distingue.

### Mes semaines

Nouvel écran `lib/screens/saved_weeks_screen.dart`, ouvert par un bouton « Mes semaines » depuis « Ma semaine », y compris depuis l'état vide. La barre de navigation reste à quatre onglets.

Chaque semaine est une ligne dépliable :

- titre : le nom ; sous-titre : date, « 14/14 repas · 2 personnes » ;
- dépliée : les repas jour par jour ;
- menu : Réutiliser, Renommer, Supprimer (avec confirmation).

### Réutiliser

Après confirmation du remplacement de la semaine actuelle, le modèle est copié comme semaine courante avec un nouvel identifiant ; le modèle reste intact. Les réglages de « Mes choix » reprennent ceux du modèle et les coches de courses sont remises à zéro. La recopie des options dans le formulaire, aujourd'hui dans `_load`, est extraite dans une méthode partagée.

### Hors périmètre

Notes sur les recettes, tri du catalogue par favoris, modification d'un modèle enregistré.

## 4. Gestion des erreurs

### Recette retirée du catalogue

`shoppingList` lève `StateError('Recette du planning introuvable.')` et elle est appelée pendant le rendu de l'onglet « Courses ».

Une fonction de domaine `reconcile(plan, recipes)` retire les repas dont la recette n'existe plus et les ajoute aux créneaux vides avec le motif « Recette retirée du catalogue ». Elle est appelée :

- à la réutilisation d'un modèle ;
- au chargement de la semaine courante dans `_load` (défaut déjà présent : le catalogue peut être réimporté alors que le planning est conservé).

Dans « Mes semaines », un repas concerné s'affiche « Recette retirée ».

### Échecs d'écriture

- **Favori** : mise à jour immédiate du cœur ; en cas d'échec, retour à l'état précédent et message.
- **Enregistrer, renommer, supprimer, réutiliser** : message d'erreur et état inchangé, comme `_generate`.
- **Web** : un `false` renvoyé par `shared_preferences` lève une `StateError`, comme `savePlan`.

### Données illisibles

Une semaine enregistrée dont le JSON ne se décode pas est ignorée, sans faire échouer la liste.

### Migration

`onUpgrade` s'exécute dans une transaction : en cas d'échec, la base reste en version 1 et l'écran d'erreur existant propose « Réessayer ».

## 5. Tests

| Niveau | Cas |
|---|---|
| Domaine | Favori préféré à score égal ; aliment préféré qui l'emporte sur un favori ; favori exclu jamais servi ; favori non répété avant les autres ; identifiant inconnu ignoré ; ancien JSON sans `favorite_recipes` relu ; sérialisation de `SavedWeek` ; `reconcile` avec et sans recette manquante ; liste de courses après `reconcile` |
| Widgets | Cœur activé depuis le catalogue et depuis la fiche ; filtre « Favoris » ignorant « Mes choix » ; nom vide refusé ; réutilisation qui remplace la semaine ; suppression confirmée ; retour arrière du cœur en cas d'échec |
| Repository | Migration v1 vers v2 conservant le dernier planning ; favoris conservés après réimport du catalogue |

Les tests du repository SQLite demandent `sqflite_common_ffi` en dépendance de développement.
