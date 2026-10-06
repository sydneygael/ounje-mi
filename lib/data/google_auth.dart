import 'package:google_sign_in/google_sign_in.dart';

import 'drive_backup_service.dart';

/// Connexion Google via le plugin `google_sign_in`, limitée au dossier privé
/// de l'application sur Drive.
class GoogleSignInAuth implements GoogleAuth {
  GoogleSignInAuth(this.serverClientId);

  /// Identifiant du client OAuth de type « Application Web ».
  final String serverClientId;
  static const _scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  Future<void>? _initialized;
  GoogleSignInAccount? _account;
  String? _token;

  Future<void> _initialize() => _initialized ??=
      GoogleSignIn.instance.initialize(serverClientId: serverClientId);

  @override
  Future<String?> restore() async {
    await _initialize();
    // Annulation et interface indisponible renvoient null sans erreur.
    _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    return _account?.email;
  }

  @override
  Future<String?> signIn() async {
    await _initialize();
    try {
      _account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
    return _account?.email;
  }

  @override
  Future<void> signOut() async {
    await _initialize();
    await GoogleSignIn.instance.signOut();
    _account = null;
    _token = null;
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final account = _account;
    if (account == null) {
      throw const DriveBackupException(DriveError.signedOut);
    }
    final client = account.authorizationClient;
    final previous = _token;
    if (forceRefresh && previous != null) {
      // Le jeton en cache a été refusé par Drive.
      await client.clearAuthorizationToken(accessToken: previous);
    }
    try {
      final authorization = await client.authorizationForScopes(_scopes) ??
          await client.authorizeScopes(_scopes);
      return _token = authorization.accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const DriveBackupException(DriveError.permissionDenied);
      }
      rethrow;
    }
  }
}
