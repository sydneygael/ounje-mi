import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ounje_mi/data/drive_backup_service.dart';
import 'package:ounje_mi/domain/backup.dart';

class FakeAuth implements GoogleAuth {
  int tokens = 0;
  int refreshes = 0;
  @override
  Future<String?> restore() async => 'moi@example.com';
  @override
  Future<String?> signIn() async => 'moi@example.com';
  @override
  Future<void> signOut() async {}
  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    tokens++;
    if (forceRefresh) refreshes++;
    return 'jeton-$tokens';
  }
}

/// Dossier privé simulé : identifiant, date de modification et contenu.
class FakeDrive {
  final files = <String, ({DateTime modified, String content})>{};
  final requests = <http.Request>[];
  final statuses = <int>[];
  String errorBody = '';
  int _next = 1;

  void put(String id, DateTime modified, String content) =>
      files[id] = (modified: modified, content: content);

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (statuses.isNotEmpty) {
      final status = statuses.removeAt(0);
      if (status != 200) return http.Response(errorBody, status);
    }
    final path = request.url.path;
    final id = request.url.pathSegments.last;
    switch (request.method) {
      case 'GET' when path == '/drive/v3/files':
        final sorted = files.entries.toList()
          ..sort((a, b) => b.value.modified.compareTo(a.value.modified));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'files': [
                for (final file in sorted)
                  {
                    'id': file.key,
                    'modifiedTime': file.value.modified.toIso8601String(),
                  },
              ],
            }),
          ),
          200,
        );
      case 'GET':
        return http.Response.bytes(utf8.encode(files[id]!.content), 200);
      case 'POST':
        final parts = request.body.split('\r\n\r\n');
        put('f${_next++}', DateTime.utc(2026, 10, 6),
            parts.last.split('\r\n').first);
        return http.Response('{}', 200);
      case 'PATCH':
        put(id, DateTime.utc(2026, 10, 6), request.body);
        return http.Response('{}', 200);
      case 'DELETE':
        files.remove(id);
        return http.Response('', 204);
    }
    return http.Response('', 404);
  }
}

void main() {
  late FakeAuth auth;
  late FakeDrive drive;
  late GoogleDriveBackupService service;
  final backup = AppBackup(
    savedAt: DateTime.utc(2026, 10, 5, 18, 30),
    plan: null,
    favorites: {'bm-176'},
    savedWeeks: const [],
  );
  final content = jsonEncode(backup.toJson());
  setUp(() {
    auth = FakeAuth();
    drive = FakeDrive();
    service = GoogleDriveBackupService(
      auth: auth,
      client: MockClient(drive.handle),
    );
  });
  Iterable<String> methods() => drive.requests.map((r) => r.method);

  test('le premier envoi crée le fichier dans le dossier privé', () async {
    await service.upload(backup);
    expect(methods(), ['GET', 'POST']);
    final list = drive.requests.first;
    expect(list.url.queryParameters['spaces'], 'appDataFolder');
    expect(list.headers['Authorization'], 'Bearer jeton-1');
    final create = drive.requests.last;
    expect(create.url.path, '/upload/drive/v3/files');
    expect(create.url.queryParameters['uploadType'], 'multipart');
    expect(create.headers['Content-Type'], startsWith('multipart/related'));
    expect(create.body, contains('"parents":["appDataFolder"]'));
    expect(create.body, contains(GoogleDriveBackupService.fileName));
    expect(drive.files.values.single.content, content);
  });
  test('un envoi suivant remplace le fichier existant', () async {
    drive.put('ancien', DateTime.utc(2026, 10, 1), '{}');
    await service.upload(backup);
    expect(methods(), ['GET', 'PATCH']);
    expect(drive.requests.last.url.path, '/upload/drive/v3/files/ancien');
    expect(drive.files.keys, ['ancien']);
    expect(drive.files['ancien']!.content, content);
  });
  test('les doublons sont supprimés, le plus récent est remplacé', () async {
    drive.put('vieux', DateTime.utc(2026, 9, 1), '{}');
    drive.put('récent', DateTime.utc(2026, 10, 1), '{}');
    await service.upload(backup);
    expect(methods(), ['GET', 'PATCH', 'DELETE']);
    expect(drive.files.keys, ['récent']);
  });
  test('un doublon impossible à supprimer ne fait pas échouer', () async {
    drive.put('vieux', DateTime.utc(2026, 9, 1), '{}');
    drive.put('récent', DateTime.utc(2026, 10, 1), '{}');
    drive.statuses.addAll([200, 200, 500]);
    await service.upload(backup);
    expect(drive.files['récent']!.content, content);
  });
  test('téléchargement sans fichier', () async {
    expect(await service.download(), isNull);
    expect(await service.lastBackupTime(), isNull);
  });
  test('téléchargement du fichier le plus récent', () async {
    drive.put('vieux', DateTime.utc(2026, 9, 1), '{"format":1}');
    drive.put('récent', DateTime.utc(2026, 10, 1, 8), content);
    final restored = await service.download();
    expect(restored?.toJson(), backup.toJson());
    expect(drive.requests.last.url.queryParameters['alt'], 'media');
    expect(await service.lastBackupTime(), DateTime.utc(2026, 10, 1, 8));
  });
  test('un contenu illisible ou trop récent remonte tel quel', () async {
    drive.put('a', DateTime.utc(2026, 10, 1), 'pas du json');
    await expectLater(
      service.download(),
      throwsA(isA<BackupFormatException>()),
    );
    drive.put('a', DateTime.utc(2026, 10, 1), '{"format":2}');
    await expectLater(
      service.download(),
      throwsA(isA<BackupTooRecentException>()),
    );
  });
  test('un jeton refusé est renouvelé une fois', () async {
    drive.statuses.addAll([401, 200]);
    expect(await service.lastBackupTime(), isNull);
    expect(auth.tokens, 2);
    expect(auth.refreshes, 1);
    expect(drive.requests.last.headers['Authorization'], 'Bearer jeton-2');
  });
  test('deux refus de suite déconnectent', () async {
    drive.statuses.addAll([401, 401, 200]);
    await expectLater(
      service.lastBackupTime(),
      throwsA(
        isA<DriveBackupException>()
            .having((e) => e.kind, 'kind', DriveError.signedOut),
      ),
    );
    expect(drive.requests.length, 2);
  });
  test('quota, autorisation et erreur serveur', () async {
    Future<void> expectError(int status, DriveError kind) async {
      drive.statuses
        ..clear()
        ..add(status);
      await expectLater(
        service.upload(backup),
        throwsA(
          isA<DriveBackupException>()
              .having((e) => e.kind, 'kind', kind)
              .having((e) => e.statusCode, 'statusCode', status),
        ),
      );
    }

    drive.errorBody =
        '{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}';
    await expectError(403, DriveError.quota);
    drive.errorBody =
        '{"error":{"errors":[{"reason":"insufficientPermissions"}]}}';
    await expectError(403, DriveError.permissionDenied);
    await expectError(500, DriveError.http);
  });
  test('une erreur réseau est signalée comme telle', () async {
    final offline = GoogleDriveBackupService(
      auth: auth,
      client: MockClient((_) async => throw http.ClientException('hors ligne')),
    );
    await expectLater(
      offline.download(),
      throwsA(
        isA<DriveBackupException>()
            .having((e) => e.kind, 'kind', DriveError.network),
      ),
    );
  });
}
