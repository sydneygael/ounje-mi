# Sauvegarde sur Google Drive — design

Date : 6 octobre 2026. Statut : design validé, non implémenté.

## Objectif

Ne pas perdre ses données : sauvegarder la semaine courante, les favoris et les semaines enregistrées dans Google Drive, puis les restaurer après un changement de téléphone ou une réinstallation. Un seul appareil à la fois, sur **Android** uniquement.

## Décisions

| Sujet | Décision |
|---|---|
| Besoin couvert | Sauvegarde et restauration. Pas de synchronisation entre appareils ni de partage. |
| Plateforme | Android. L'accès à l'écran est masqué ailleurs. |
| Approche | Intégration directe de l'API Google Drive, avec connexion Google dans l'appli. |
| Déclenchement | Bouton « Sauvegarder maintenant » uniquement ; rien ne part sans action explicite. |
| Emplacement | Dossier privé de l'appli (`appDataFolder`), invisible dans Drive. |
| Restauration | Remplacement complet des données locales, après confirmation. |
| Historique | Un seul fichier, écrasé à chaque sauvegarde. |
| Appels Drive | Paquet `http` et trois appels REST, sans `googleapis`. |

Approches écartées : la sauvegarde automatique d'Android (aucun bouton, aucun contrôle, restauration seulement à l'installation) ; l'export/import d'un fichier par le sélecteur du système (manuel, sans lien direct avec Drive).

## 1. Vue d'ensemble et prérequis

### Contenu de la sauvegarde

Un fichier `ounje-mi-backup.json` dans le dossier privé de l'appli :

```json
{
  "format": 1,
  "saved_at": "2026-10-05T18:30:00Z",
  "plan": {},
  "favorites": ["bm-069"],
  "saved_weeks": []
}
```

- `plan` reprend `MealPlan.toJson` et vaut `null` s'il n'y a pas de semaine courante. Les réglages de « Mes choix » sont déjà dans `plan.options`.
- `saved_weeks` reprend `SavedWeek.toJson`.
- Le catalogue, les photos et les coches de courses n'y figurent pas.

### Découpage du code

| Élément | Rôle |
|---|---|
| `lib/domain/backup.dart` | Classe `AppBackup`, sérialisation, contrôle du champ `format` |
| `RecipeRepository.exportBackup()` | Lit la semaine courante, les favoris et les semaines enregistrées |
| `RecipeRepository.importBackup(backup)` | Remplace ces données en une seule transaction SQLite |
| `lib/data/drive_backup_service.dart` | Connexion Google, envoi et téléchargement du fichier |
| `lib/screens/backup_screen.dart` | Écran « Sauvegarde » |

Le service Drive est derrière une interface, comme le repository, pour que les tests de widgets utilisent un faux. La connexion Google est elle-même derrière une petite interface qui fournit le jeton d'accès.

`exportBackup` et `importBackup` sont écrits pour les deux implémentations du repository (SQLite et `shared_preferences`) : l'interface est commune et les tests de widgets tournent sans SQLite.

### Dépendances

- `google_sign_in` : connexion et jeton d'accès.
- `http` : appels REST à Drive.

### Autorisation

Uniquement la portée `drive.appdata`. L'appli ne voit aucun autre fichier du Drive. Cette portée n'est pas classée sensible : pas de vérification par Google.

### Prérequis hors code

1. Remplacer `com.example.ounje_mi` par un identifiant définitif. Le client OAuth Android y est lié ; le changer ensuite oblige à tout reconfigurer.
2. Créer un projet Google Cloud, activer l'API Drive, configurer l'écran de consentement en mode test avec le compte de l'utilisateur comme testeur.
3. Créer un client OAuth Android (nom du paquet et empreinte SHA-1) et un client OAuth Web, dont l'identifiant est passé à `google_sign_in`.

Le README perd la mention « Aucune clé API n'est nécessaire ». L'appli reste entièrement utilisable sans connexion Google.

## 2. Écran et parcours

### Accès

Une icône nuage dans la barre de titre de `HomeScreen`, à côté de « À propos des recettes ». La barre de navigation reste à quatre onglets.

### États de l'écran

- **Non connecté** : une phrase expliquant ce qui est sauvegardé et que l'appli n'accède à aucun autre fichier du Drive ; bouton « Se connecter à Google ».
- **Connecté** : adresse du compte ; « Dernière sauvegarde : 5 octobre à 18 h 30 » ou « Aucune sauvegarde » ; actions « Sauvegarder maintenant », « Restaurer », « Se déconnecter ».

La date de dernière sauvegarde est lue sur Drive à l'ouverture de l'écran et n'est pas stockée sur le téléphone : elle reste juste après une réinstallation.

Pendant un envoi ou un téléchargement, les boutons sont désactivés et un indicateur de progression s'affiche.

### Sauvegarder

1. `exportBackup()` lit l'état local.
2. Le service cherche `ounje-mi-backup.json` dans `appDataFolder`.
3. S'il existe, son contenu est remplacé ; sinon il est créé.
4. La date affichée est mise à jour ; message « Sauvegarde effectuée ».

Garde-fou : si le téléphone ne contient ni semaine courante, ni favori, ni semaine enregistrée, et qu'une sauvegarde existe déjà, un dialogue demande confirmation avant d'écraser. C'est le cas du nouveau téléphone où l'on appuie sur « Sauvegarder » au lieu de « Restaurer ».

### Restaurer

1. Le fichier est téléchargé et décodé, sans rien modifier en local.
2. Un dialogue résume : « Sauvegarde du 5 octobre : 12 favoris, 3 semaines enregistrées. Les données actuelles de ce téléphone seront remplacées. »
3. Après confirmation, `importBackup()` remplace tout dans une seule transaction.
4. De retour à l'accueil, `_load` est rappelé. Il applique déjà `reconcile` : un repas dont la recette n'existe plus devient un créneau vide signalé.

### Hors périmètre

Sauvegarde automatique, historique de plusieurs sauvegardes, fusion à la restauration, web, iOS et macOS, changement de compte sans se déconnecter.

## 3. Gestion des erreurs

Principe commun, repris de `_generate` : un message clair, l'état local inchangé, l'utilisateur peut réessayer. Aucune reprise automatique.

### Connexion

| Cas | Comportement |
|---|---|
| Connexion annulée par l'utilisateur | Retour silencieux à l'état « non connecté » |
| Autorisation Drive refusée | « L'accès au dossier de sauvegarde est nécessaire. » et bouton pour redemander |
| Mauvaise configuration OAuth | « Connexion impossible », détail technique dans les journaux |

### Réseau et Drive

| Cas | Comportement |
|---|---|
| Pas de réseau, délai dépassé (30 s) | « Pas de connexion. Réessayez plus tard. » |
| Jeton expiré (401) | Un renouvellement silencieux puis une seconde tentative ; en cas de nouvel échec, retour à « non connecté » |
| Quota Drive plein (403) | « Espace Google Drive insuffisant. » |
| Autre réponse d'erreur | « Sauvegarde impossible » ou « Restauration impossible », avec le code HTTP |

### Restauration

Tout est vérifié avant d'écrire :

- **Aucun fichier sur Drive** : « Aucune sauvegarde sur ce compte. »
- **JSON illisible ou `format` absent** : « Sauvegarde illisible. »
- **`format` supérieur au format connu** : « Cette sauvegarde vient d'une version plus récente de l'appli. Mettez l'appli à jour. » Pas de lecture partielle.
- **Semaine enregistrée indécodable** : ignorée, et le dialogue de confirmation l'indique (« 1 semaine illisible ignorée »), comme `loadSavedWeeks`.
- **Favori dont la recette n'existe plus** : conservé tel quel ; le moteur l'ignore déjà.
- **Échec pendant `importBackup()`** : la transaction est annulée, les données d'avant restent intactes.

Dans les quatre premiers cas, rien n'est modifié en local.

### Sauvegarde

L'écriture remplace le contenu du fichier en un seul appel : un envoi interrompu laisse l'ancienne sauvegarde en place. Si deux fichiers du même nom existent, le plus récent est utilisé et les autres sont supprimés à la sauvegarde suivante.

## 4. Tests

| Niveau | Cas |
|---|---|
| Domaine (`test/backup_test.dart`) | Aller-retour `toJson`/`fromJson` ; `plan` nul relu ; `format` absent ou non entier refusé ; `format` plus récent refusé avec une erreur distincte ; semaine indécodable ignorée et comptée |
| Repository (`test/repository_test.dart`) | `exportBackup` renvoie ce qui a été écrit ; `importBackup` remplace tout, y compris en retirant favoris et semaines absents ; `plan` nul vide la semaine courante ; échec en cours d'import sans perte ; catalogue non touché |
| Service Drive (`test/drive_backup_service_test.dart`, `MockClient`) | Création au premier envoi ; mise à jour ensuite, sans second fichier ; téléchargement sans fichier ; 401 suivi d'un seul renouvellement ; 403 de quota et erreur réseau en erreurs typées ; deux fichiers du même nom, le plus récent lu |
| Widgets (`test/widget_test.dart`, faux service) | États non connecté et connecté ; date mise à jour après sauvegarde ; confirmation sur téléphone vide ; restauration avec compteurs puis données visibles à l'accueil ; restauration annulée sans changement ; erreur affichée et boutons réactivés |

La connexion Google n'est pas testée automatiquement.

### Vérification manuelle

Indispensable, sur un vrai téléphone Android, aucune compilation native n'ayant encore été faite pour ce projet :

1. connexion, sauvegarde, désinstallation, réinstallation, restauration ;
2. mode avion pendant une sauvegarde et pendant une restauration ;
3. refus de l'autorisation Drive.
