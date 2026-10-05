import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp('ounje_api_test');
  final config = File('${temporary.path}/packages.json');
  await config.writeAsString(jsonEncode({
    'configVersion': 2,
    'packages': [
      {
        'name': 'ounje_mi',
        'rootUri': Directory.current.uri.toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.5',
      }
    ],
  }));
  final process = await Process.start(Platform.resolvedExecutable, [
    '--disable-dart-dev',
    '--packages=${config.path}',
    'bin/recipe_api.dart',
    '0',
  ]);
  final errors = <String>[];
  final stderr = process.stderr.transform(utf8.decoder).listen(errors.add);
  final client = HttpClient();
  try {
    final line = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 15));
    final base = RegExp(r'http://127\.0\.0\.1:\d+').firstMatch(line)!.group(0)!;
    Future<(int, dynamic)> call(String path, {Object? body}) async {
      final request = await client.openUrl(
        body == null ? 'GET' : 'POST',
        Uri.parse('$base$path'),
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      return (
        response.statusCode,
        jsonDecode(await response.transform(utf8.decoder).join()),
      );
    }

    void check(bool value, String reason) {
      if (!value) throw StateError(reason);
    }

    final health = await call('/health');
    check(health.$1 == 200 && health.$2['recipes'] == 146, 'health');
    final filtered = await call('/recipes?food_ids=brocoli&limit=2');
    check(
      filtered.$1 == 200 && filtered.$2['items'].length == 2,
      'catalog filter',
    );
    final created = await call('/plans', body: {'days': 2, 'servings': 3});
    check(
      created.$1 == 201 &&
          created.$2['meals'].length == 4 &&
          created.$2['complete'] == true,
      'create plan',
    );
    final read = await call('/plans/${created.$2['id']}');
    check(jsonEncode(read.$2) == jsonEncode(created.$2), 'roundtrip plan');
    final shopping = await call('/plans/${created.$2['id']}/shopping-list');
    check(
      shopping.$1 == 200 && shopping.$2['items'].isNotEmpty,
      'shopping list',
    );
    check(
      (await call('/plans', body: {'servings': 0})).$1 == 400,
      'invalid portions',
    );
    check(
      (await call('/plans', body: {'vegetarian': 'true'})).$1 == 400,
      'invalid type',
    );
    check(
      (await call(
            '/plans',
            body: {
              'excluded_foods': ['imaginaire'],
            },
          ))
              .$1 ==
          400,
      'unknown food',
    );
    final partial = await call('/plans', body: {'max_minutes': 1});
    check(
      partial.$1 == 201 && partial.$2['unfilled_slots'].length == 14,
      'partial plan',
    );
    check((await call('/recipes/bm-999')).$1 == 404, 'unknown recipe');
    final photoRequest = await client.getUrl(
      Uri.parse('$base/photos/bm-176.jpg'),
    );
    final photoResponse = await photoRequest.close();
    final bytes = await photoResponse.fold<List<int>>(
      [],
      (a, b) => a..addAll(b),
    );
    check(
      photoResponse.statusCode == 200 && bytes[0] == 0xff && bytes[1] == 0xd8,
      'photo',
    );
    stdout.writeln('11 vérifications API Dart réussies.');
  } finally {
    client.close(force: true);
    process.kill();
    await process.exitCode;
    await stderr.cancel();
    await temporary.delete(recursive: true);
  }
}
