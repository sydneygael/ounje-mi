# Sauvegarde sur Google Drive — plan d'implémentation

Date : 6 octobre 2026. Design : [2026-10-06-sauvegarde-google-drive-design.md](2026-10-06-sauvegarde-google-drive-design.md).

## Ordre et dépendances

| # | Tâche | Dépend de | Qui |
|---|---|---|---|
| 0 | Identifiant définitif de l'appli et permission réseau | choix de l'identifiant | code |
| 1 | Domaine : `AppBackup` | — | code |
| 2 | Repository : `exportBackup` / `importBackup` | 1 | code |
| 3 | Service Drive (REST, sans connexion réelle) | 1 | code |
| 4 | Connexion Google (`google_sign_in`) | 3 | code |
| 5 | Écran « Sauvegarde » et accès depuis l'accueil | 2, 3 | code |
| 6 | Projet Google Cloud et clients OAuth | 0 | **vous** |
| 7 | Branchement dans `main.dart`, README | 4, 5, 6 | code |
| 8 | Vérification manuelle sur téléphone | 7 | **vous** |

Les tâches 1 à 5 se font et se testent sans compte Google ni téléphone. Tant que l'identifiant client de la tâche 6 n'est pas renseigné, l'icône nuage reste masquée : le code peut être fusionné avant la configuration.

Chaque tâche se termine par `dart format lib test tool bin`, `flutter analyze`, `flutter test`, puis un commit. La CI lance aussi `flutter build web` : à vérifier après les tâches 4 et 7, qui ajoutent `google_sign_in`.

## Tâche 0 — Identifiant de l'appli et permission réseau

Choisir l'identifiant, par exemple `com.sydneygael.ounjemi` (noté `<ID>` ci-dessous). Il ne doit plus changer ensuite.

- `android/app/build.gradle.kts` : `namespace` et `applicationId` passent à `<ID>` ; retirer le `TODO` de la ligne 18.
- Déplacer `android/app/src/main/kotlin/com/example/ounje_mi/MainActivity.kt` dans le dossier correspondant à `<ID>` et corriger sa ligne `package`.
- `android/app/src/main/AndroidManifest.xml` : ajouter `<uses-permission android:name="android.permission.INTERNET"/>`. Elle n'existe aujourd'hui que dans les manifestes `debug` et `profile` ; sans elle, la sauvegarde échoue en version release.
- Les identifiants iOS et macOS ne sont pas modifiés (hors périmètre).

Conséquence : Android voit une nouvelle appli. Une installation existante sous `com.example.ounje_mi` reste à côté avec ses données, qui ne sont pas reprises.

Vérification : `flutter build apk --debug`. C'est la première compilation Android du projet ; prévoir de corriger d'éventuels problèmes de configuration Gradle sans rapport avec cette fonctionnalité.

Commit : `chore: set final Android application id and internet permission`.

## Tâche 1 — Domaine : `AppBackup`

Nouveau fichier `lib/domain/backup.dart`, sans dépendance Flutter.

```dart
class BackupFormatException implements Exception { … }   // illisible
class BackupTooRecentException implements Exception { … } // format > connu

class AppBackup {
  static const currentFormat = 1;
  final DateTime savedAt;
  final MealPlan? plan;
  final Set<String> favorites;
  final List<SavedWeek> savedWeeks;
  final int skippedWeeks;          // semaines indécodables, non sérialisé
  bool get isEmpty => plan == null && favorites.isEmpty && savedWeeks.isEmpty;
  Map<String, dynamic> toJson();
  factory AppBackup.fromJson(Map<String, dynamic> json);
  static AppBackup decode(String text); // jsonDecode + fromJson
}
```

Règles de `fromJson` :

- `format` absent ou non entier, `saved_at` invalide, `favorites` ou `saved_weeks` qui ne sont pas des listes, `plan` présent mais indécodable : `BackupFormatException`.
- `format > currentFormat` : `BackupTooRecentException`, testé avant toute autre lecture.
- Chaque entrée de `saved_weeks` est décodée dans un `try` ; un échec incrémente `skippedWeeks`.
- `decode` transforme une `FormatException` de `jsonDecode`, ou un JSON qui n'est pas un objet, en `BackupFormatException`.
- `toJson` trie les favoris, comme `PlanOptions.toJson`.

Tests, nouveau fichier `test/backup_test.dart` :

1. aller-retour complet (semaine, favoris, deux semaines enregistrées) ;
2. `plan` nul relu, `isEmpty` vrai quand tout est vide ;
3. `format` absent, puis `format: "1"` : `BackupFormatException` ;
4. `format: 2` : `BackupTooRecentException` ;
5. une semaine valide et une indécodable : une semaine lue, `skippedWeeks == 1` ;
6. `decode('pas du json')` et `decode('[]')` : `BackupFormatException`.

Commit : `feat: add backup model with versioned format`.

## Tâche 2 — Repository : `exportBackup` / `importBackup`

Fichier `lib/data/recipe_repository.dart`.

Interface :

```dart
Future<AppBackup> exportBackup();
Future<void> importBackup(AppBackup backup);
```

`exportBackup` : assemble `loadPlan()`, `loadFavorites()` et `loadSavedWeeks()` avec `savedAt = DateTime.now().toUtc()`.

`importBackup`, SQLite : une seule `transaction` qui vide `plans`, `favorites` et `saved_weeks`, puis insère le contenu de la sauvegarde avec les mêmes colonnes que `savePlan`, `setFavorite` et `saveWeek`. Les insertions gardent l'algorithme de conflit par défaut : une erreur annule tout.

`importBackup`, `shared_preferences` : écrit `ounje_mi_saved_weeks`, `ounje_mi_favorites`, puis `ounje_mi_latest_plan` (ou `remove` si `plan` est nul). Un retour `false` lève la même `StateError` que `savePlan`. Ces trois écritures ne sont pas atomiques ; c'est accepté, cette branche ne sert pas sur Android.

Les doublons de test : ajouter les deux méthodes à `FakeRepository` et `FailingRepository` dans `test/widget_test.dart`, sinon la suite ne compile plus.

Tests dans `test/repository_test.dart`, à l'intérieur de `sharedScenarios()` pour couvrir les deux stockages :

1. `exportBackup` renvoie la semaine, les favoris et les semaines écrits juste avant ;
2. `importBackup` remplace tout : un favori et une semaine absents de la sauvegarde disparaissent, une nouvelle instance du repository relit le résultat ;
3. `plan` nul : `loadPlan()` renvoie `null` ensuite.

Tests propres à SQLite, dans le groupe existant :

4. deux semaines de même `id` dans la sauvegarde provoquent une erreur de clé primaire : l'import échoue et la semaine, les favoris et les semaines d'avant sont intacts ;
5. après un import, `loadRecipes()` renvoie toujours 146 recettes.

Commit : `feat: export and import backups in the repository`.

## Tâche 3 — Service Drive

Dépendance : `flutter pub add http`.

Nouveau fichier `lib/data/drive_backup_service.dart`.

```dart
/// Fournit le jeton ; implémenté par google_sign_in à la tâche 4.
abstract class GoogleAuth {
  Future<String?> restore();  // connexion silencieuse, adresse ou null
  Future<String?> signIn();   // null si l'utilisateur annule
  Future<void> signOut();
  Future<String> accessToken({bool forceRefresh = false});
}

enum DriveError { network, signedOut, permissionDenied, quota, http }

class DriveBackupException implements Exception {
  final DriveError kind;
  final int? statusCode;
}

abstract class DriveBackupService {
  Future<String?> restoreAccount();
  Future<String?> signIn();
  Future<void> signOut();
  Future<DateTime?> lastBackupTime();
  Future<void> upload(AppBackup backup);
  Future<AppBackup?> download();   // null : aucune sauvegarde
}

class GoogleDriveBackupService implements DriveBackupService {
  GoogleDriveBackupService({required GoogleAuth auth, http.Client? client});
}
```

Appels REST, tous avec `Authorization: Bearer <jeton>` et un délai de 30 s :

| Besoin | Requête |
|---|---|
| Trouver le fichier | `GET /drive/v3/files?spaces=appDataFolder&q=name='ounje-mi-backup.json'&orderBy=modifiedTime desc&fields=files(id,modifiedTime)` |
| Lire | `GET /drive/v3/files/{id}?alt=media` |
| Créer | `POST /upload/drive/v3/files?uploadType=multipart`, métadonnées `{"name": …, "parents": ["appDataFolder"]}` |
| Remplacer | `PATCH /upload/drive/v3/files/{id}?uploadType=media` |
| Supprimer un doublon | `DELETE /drive/v3/files/{id}` |

Comportements :

- `lastBackupTime` ne télécharge rien : il renvoie le `modifiedTime` du premier résultat de la recherche.
- `upload` : recherche, puis remplacement du plus récent ou création ; les autres fichiers du même nom sont supprimés ensuite, et un échec de cette suppression n'annule pas la sauvegarde.
- `download` : recherche, lecture du plus récent, `AppBackup.decode`. Les exceptions de format remontent telles quelles.
- Une méthode privée `_send` centralise les erreurs : sur un 401, un seul nouvel essai avec `accessToken(forceRefresh: true)`, puis `DriveError.signedOut` ; 403 avec le motif `storageQuotaExceeded` : `quota` ; autre 403 : `permissionDenied` ; `SocketException`, `ClientException` ou `TimeoutException` : `network` ; tout autre code hors 2xx : `http` avec le code.

Tests, nouveau fichier `test/drive_backup_service_test.dart`, avec `MockClient` de `package:http/testing.dart` et un faux `GoogleAuth` qui compte les demandes de jeton :

1. premier envoi : un `POST` multipart contenant `appDataFolder`, aucun `PATCH` ;
2. envoi suivant : un `PATCH` sur l'identifiant existant, aucun `POST` ;
3. deux fichiers du même nom : le plus récent est remplacé, l'autre reçoit un `DELETE` ;
4. `download` sans fichier : `null` ;
5. `download` avec un fichier : `AppBackup` relu à l'identique ;
6. `lastBackupTime` : date du plus récent, et `null` sans fichier ;
7. 401 puis 200 : succès, deux demandes de jeton dont une forcée ;
8. 401 deux fois : `DriveError.signedOut`, pas de troisième tentative ;
9. 403 `storageQuotaExceeded` : `quota` ; 500 : `http` avec `statusCode == 500` ;
10. client qui lève `ClientException` : `network`.

Commit : `feat: add Drive backup service over REST`.

## Tâche 4 — Connexion Google

Dépendance : `flutter pub add google_sign_in`.

Nouveau fichier `lib/data/google_auth.dart` : `GoogleSignInAuth implements GoogleAuth`, construit avec l'identifiant du client OAuth Web (`serverClientId`) et la portée `https://www.googleapis.com/auth/drive.appdata`.

- `restore` : tentative de connexion silencieuse.
- `signIn` : connexion interactive ; une annulation par l'utilisateur renvoie `null` au lieu de lever une erreur.
- `accessToken` : jeton autorisé pour la portée ; demande l'autorisation si elle manque ; `forceRefresh` invalide d'abord le jeton en cache. Un refus lève `DriveBackupException(DriveError.permissionDenied)`.
- `signOut` : déconnexion.

L'API de `google_sign_in` a été refondue en version 7 (instance unique, initialisation explicite, autorisation des portées séparée de l'authentification). **Avant d'écrire ce fichier, lire le README de la version installée** dans le cache pub et s'y conformer, plutôt que de suivre d'anciens exemples.

Ce fichier n'a pas de test automatique : il ne contient que la traduction vers le plugin. Il est couvert par la tâche 8.

Vérification : `flutter analyze`, `flutter build web` (le paquet inclut une implémentation web qui doit compiler même si elle n'est jamais appelée), `flutter build apk --debug`.

Commit : `feat: add Google sign-in for Drive backups`.

## Tâche 5 — Écran « Sauvegarde »

### `lib/screens/backup_screen.dart`

```dart
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.repository, required this.service});
}
```

État : `account` (adresse ou `null`), `lastBackup`, `busy`, `loading`. L'écran se ferme avec `Navigator.pop(context, true)` après une restauration réussie, `false` sinon.

- `initState` : `restoreAccount()`, puis `lastBackupTime()` si un compte est connecté.
- Non connecté : texte d'explication et bouton « Se connecter à Google ».
- Connecté : adresse, ligne « Dernière sauvegarde : … » formatée avec `frenchDate` (déjà utilisée par `home_screen.dart`) et l'heure, ou « Aucune sauvegarde » ; boutons « Sauvegarder maintenant », « Restaurer », « Se déconnecter ».
- `busy` désactive les trois boutons et affiche un `LinearProgressIndicator`.

`_save` : `exportBackup()` ; si `backup.isEmpty && lastBackup != null`, dialogue « Ce téléphone ne contient aucune donnée. Remplacer la sauvegarde du … ? » ; puis `upload`, relecture de la date, message « Sauvegarde effectuée ».

`_restore` : `download()` ; `null` donne « Aucune sauvegarde sur ce compte. » ; sinon dialogue de résumé (date, nombre de favoris, nombre de semaines, ligne « N semaine(s) illisible(s) ignorée(s) » si `skippedWeeks > 0`) ; après confirmation, `importBackup`, puis fermeture avec `true`.

Une méthode `_message(Object error)` traduit les erreurs en phrases du design : `DriveBackupException` selon `kind`, `BackupFormatException`, `BackupTooRecentException`, et un repli « Sauvegarde impossible : … » ou « Restauration impossible : … ». `DriveError.signedOut` repasse en plus l'écran à l'état non connecté.

### `lib/screens/home_screen.dart`

- `HomeScreen` reçoit un paramètre facultatif `DriveBackupService? backupService`.
- Dans `actions` de l'`AppBar`, avant « À propos des recettes » : si `backupService != null`, un `IconButton` (`Icons.cloud_outlined`, infobulle « Sauvegarde ») qui appelle `_openBackup`.
- `_openBackup` pousse `BackupScreen` ; si le résultat est `true`, `checked.clear()` puis `_load()`, qui recharge tout et applique `reconcile`.

Limite connue : si la sauvegarde restaurée n'a pas de semaine courante, `_load` ne touche pas au formulaire « Mes choix », qui garde ses valeurs en mémoire jusqu'au redémarrage.

### Tests dans `test/widget_test.dart`

Ajouter un `FakeBackupService` en mémoire (compte, fichier distant, erreur à lever) et un groupe « sauvegarde » :

1. sans `backupService`, pas d'icône nuage ; avec, l'icône ouvre l'écran ;
2. non connecté, puis « Se connecter à Google » affiche l'adresse et « Aucune sauvegarde » ;
3. connexion annulée : l'écran reste non connecté, sans message d'erreur ;
4. « Sauvegarder maintenant » : le faux service reçoit la sauvegarde, la date s'affiche ;
5. repository vide et sauvegarde distante existante : le dialogue apparaît ; « Annuler » n'envoie rien ;
6. « Restaurer » : le dialogue affiche les compteurs ; après confirmation, retour à l'accueil, le filtre « Favoris » montre la recette restaurée et « Ma semaine » montre le planning ;
7. restauration annulée : le repository n'a pas changé ;
8. « Restaurer » sans fichier distant : « Aucune sauvegarde sur ce compte. » ;
9. service qui lève `DriveError.network` : message affiché, boutons de nouveau actifs ;
10. `BackupTooRecentException` : message de mise à jour, repository inchangé ;
11. écran sans débordement à la largeur d'un téléphone, comme les tests existants du même nom.

Commit : `feat: add backup screen with save and restore`.

## Tâche 6 — Google Cloud (à faire par vous)

1. Créer un projet sur console.cloud.google.com et y activer « Google Drive API ».
2. Écran de consentement OAuth : type externe, statut « Test », votre adresse dans les utilisateurs de test, portée `…/auth/drive.appdata`.
3. Relever l'empreinte SHA-1 de la clé qui signe l'appli : `cd android && ./gradlew signingReport`, variante `debug`. La version release est signée avec cette même clé de débogage (`build.gradle.kts`, ligne 36).
4. Créer un identifiant « ID client OAuth » de type **Android** avec `<ID>` et cette empreinte.
5. Créer un second identifiant de type **Application Web**. Son identifiant client (`….apps.googleusercontent.com`) est la valeur attendue à la tâche 7.

À savoir :

- La clé de débogage est propre à chaque ordinateur. Compiler depuis une autre machine demande d'ajouter son empreinte au client Android.
- En statut « Test », seuls les comptes listés peuvent se connecter.
- Un identifiant client n'est pas un secret ; il peut être commité dans ce dépôt privé.

## Tâche 7 — Branchement et documentation

- Nouveau fichier `lib/data/google_config.dart` : `const googleServerClientId = '';` à remplir avec la valeur de la tâche 6.
- `lib/main.dart` : construire `GoogleDriveBackupService(auth: GoogleSignInAuth(googleServerClientId))` uniquement si `!kIsWeb`, `defaultTargetPlatform == TargetPlatform.android` et `googleServerClientId.isNotEmpty` ; sinon `null`. `OunjeMiApp` transmet le service à `HomeScreen`.
- `README.md` :
  - ajouter « Sauvegarde Google Drive (Android) » aux fonctionnalités ;
  - remplacer « Aucune clé API n'est nécessaire » par : l'appli fonctionne sans compte ; la sauvegarde Drive demande la configuration de la tâche 6 ;
  - ajouter une section « Sauvegarde » : contenu du fichier, dossier privé, remplacement à la restauration, prérequis OAuth ;
  - compléter l'arborescence de la section Architecture et le nombre de tests ;
  - laisser « synchronisation entre appareils » dans les suites : cette sauvegarde ne la couvre pas.
- Passer le statut du document de design à « implémenté ».

Commit : `feat: enable Drive backup on Android and document it`.

## Tâche 8 — Vérification manuelle (à faire par vous)

Sur un téléphone Android, avec `flutter run --release` :

1. Créer une semaine, deux favoris et une semaine enregistrée. Se connecter, sauvegarder : la date s'affiche.
2. Désinstaller l'appli, la réinstaller, se connecter : la date de la sauvegarde est toujours là. Appuyer sur « Sauvegarder maintenant » : la confirmation du téléphone vide apparaît ; annuler.
3. Restaurer : la semaine, les favoris, la semaine enregistrée et les réglages de « Mes choix » sont revenus.
4. Mode avion, puis sauvegarder et restaurer : « Pas de connexion », données inchangées.
5. Se déconnecter, se reconnecter en refusant l'autorisation Drive : message et possibilité de redemander.
6. Dans Drive, Paramètres → Gérer les applications : « Ounjé Mi » apparaît avec des données masquées.

Tout écart constaté ici touche presque toujours `lib/data/google_auth.dart` ou la configuration OAuth de la tâche 6 (empreinte SHA-1, identifiant du paquet, utilisateur de test manquant).
