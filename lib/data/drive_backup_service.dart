import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/backup.dart';

/// Connexion Google et jeton d'accès limité au dossier privé de l'appli.
abstract class GoogleAuth {
  /// Connexion silencieuse ; renvoie l'adresse du compte ou `null`.
  Future<String?> restore();

  /// Connexion interactive ; renvoie `null` si l'utilisateur annule.
  Future<String?> signIn();
  Future<void> signOut();
  Future<String> accessToken({bool forceRefresh = false});
}

enum DriveError { network, signedOut, permissionDenied, quota, http }

class DriveBackupException implements Exception {
  const DriveBackupException(this.kind, {this.statusCode});
  final DriveError kind;
  final int? statusCode;
  @override
  String toString() =>
      'Google Drive : ${kind.name}${statusCode == null ? "" : " ($statusCode)"}';
}

abstract class DriveBackupService {
  Future<String?> restoreAccount();
  Future<String?> signIn();
  Future<void> signOut();
  Future<DateTime?> lastBackupTime();
  Future<void> upload(AppBackup backup);

  /// Renvoie `null` s'il n'y a aucune sauvegarde sur le compte.
  Future<AppBackup?> download();
}

class GoogleDriveBackupService implements DriveBackupService {
  GoogleDriveBackupService({required GoogleAuth auth, http.Client? client})
      : _auth = auth,
        _client = client ?? http.Client();
  static const fileName = 'ounje-mi-backup.json';
  static const _host = 'www.googleapis.com';
  static const _boundary = 'ounje-mi-backup-boundary';
  final GoogleAuth _auth;
  final http.Client _client;

  @override
  Future<String?> restoreAccount() => _auth.restore();
  @override
  Future<String?> signIn() => _auth.signIn();
  @override
  Future<void> signOut() => _auth.signOut();

  Future<http.Response> _send(
    String method,
    Uri uri, {
    String? contentType,
    String? body,
  }) async {
    for (var attempt = 0;; attempt++) {
      // Un jeton refusé est renouvelé une seule fois.
      final token = await _auth.accessToken(forceRefresh: attempt > 0);
      final request = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = contentType!;
        request.bodyBytes = utf8.encode(body);
      }
      final http.Response response;
      try {
        response = await () async {
          return http.Response.fromStream(await _client.send(request));
        }()
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        throw const DriveBackupException(DriveError.network);
      } on http.ClientException {
        throw const DriveBackupException(DriveError.network);
      }
      final status = response.statusCode;
      if (status >= 200 && status < 300) return response;
      if (status == 401) {
        if (attempt == 0) continue;
        throw const DriveBackupException(DriveError.signedOut);
      }
      if (status == 403) {
        throw DriveBackupException(
          response.body.contains('storageQuotaExceeded')
              ? DriveError.quota
              : DriveError.permissionDenied,
          statusCode: status,
        );
      }
      throw DriveBackupException(DriveError.http, statusCode: status);
    }
  }

  /// Fichiers de sauvegarde du dossier privé, le plus récent d'abord.
  Future<List<({String id, DateTime modified})>> _files() async {
    final response = await _send(
      'GET',
      Uri.https(_host, '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = '$fileName'",
        'orderBy': 'modifiedTime desc',
        'fields': 'files(id,modifiedTime)',
      }),
    );
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      return [
        for (final file in json['files'] as List)
          (
            id: (file as Map)['id'] as String,
            modified: DateTime.parse(file['modifiedTime'] as String),
          ),
      ];
    } catch (_) {
      throw DriveBackupException(
        DriveError.http,
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<DateTime?> lastBackupTime() async {
    final files = await _files();
    return files.isEmpty ? null : files.first.modified;
  }

  @override
  Future<void> upload(AppBackup backup) async {
    final content = jsonEncode(backup.toJson());
    final files = await _files();
    if (files.isEmpty) {
      final metadata = jsonEncode({
        'name': fileName,
        'parents': ['appDataFolder'],
      });
      await _send(
        'POST',
        Uri.https(_host, '/upload/drive/v3/files', {'uploadType': 'multipart'}),
        contentType: 'multipart/related; boundary=$_boundary',
        body: '--$_boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$metadata\r\n'
            '--$_boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$content\r\n'
            '--$_boundary--',
      );
      return;
    }
    // Le remplacement se fait en un appel : un envoi interrompu laisse
    // l'ancienne sauvegarde en place.
    await _send(
      'PATCH',
      Uri.https(_host, '/upload/drive/v3/files/${files.first.id}', {
        'uploadType': 'media',
      }),
      contentType: 'application/json; charset=UTF-8',
      body: content,
    );
    for (final duplicate in files.skip(1)) {
      // Le ménage des doublons ne doit pas faire échouer la sauvegarde.
      try {
        await _send(
          'DELETE',
          Uri.https(_host, '/drive/v3/files/${duplicate.id}'),
        );
      } on DriveBackupException {
        break;
      }
    }
  }

  @override
  Future<AppBackup?> download() async {
    final files = await _files();
    if (files.isEmpty) return null;
    final response = await _send(
      'GET',
      Uri.https(_host, '/drive/v3/files/${files.first.id}', {'alt': 'media'}),
    );
    try {
      return AppBackup.decode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw BackupFormatException(e.message);
    }
  }
}
