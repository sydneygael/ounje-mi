import 'dart:convert';
import 'dart:io';

import 'package:ounje_mi/domain/planner.dart';
import 'package:ounje_mi/domain/recipe.dart';

Future<void> main(List<String> args) async {
  final recipes = decodeRecipes(
    await File('assets/data/recipes.json').readAsString(),
  );
  final index = {for (final r in recipes) r.id: r};
  const planner = WeeklyPlanner();
  final directory = Directory('local/plans');
  await directory.create(recursive: true);
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    args.isEmpty ? 8000 : int.parse(args.first),
  );
  stdout.writeln('Ounjé Mi API Dart : http://127.0.0.1:${server.port}');
  await for (final request in server) {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    try {
      final token = Platform.environment['OUNJE_API_TOKEN'];
      if (token != null &&
          request.headers.value('Authorization') != 'Bearer $token') {
        response.statusCode = 401;
        response.write(jsonEncode({'error': 'unauthorized'}));
        continue;
      }
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      Object? output;
      if (request.method == 'GET' && path == '/health') {
        output = {'status': 'ok', 'recipes': recipes.length};
      } else if (request.method == 'GET' && path == '/foods') {
        final foods = <String, Food>{};
        for (final r in recipes) {
          for (final f in r.ingredients.expand((i) => i.foods)) {
            foods[f.id] = f;
          }
        }
        final found = foods.values
            .where(
              (f) => query['group'] == null || f.group == query['group'],
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        output = {
          'items': found.map((f) => {'id': f.id, 'group': f.group}).toList(),
        };
      } else if (request.method == 'GET' && path == '/recipes') {
        final ids = (query['food_ids'] ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toSet();
        final excluded = (query['exclude'] ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toSet();
        final mode = query['food_mode'] ?? 'any';
        final limit = int.parse(query['limit'] ?? '50');
        final offset = int.parse(query['offset'] ?? '0');
        final veggie = query['vegetarian'] ?? 'false';
        if (limit < 1 ||
            limit > 200 ||
            offset < 0 ||
            !{'any', 'all'}.contains(mode) ||
            !{'true', 'false'}.contains(veggie)) {
          throw ArgumentError('Filtre ou pagination invalide.');
        }
        if (!recipes.expand((r) => r.foodIds).toSet().containsAll(ids)) {
          throw ArgumentError('Aliment inconnu.');
        }
        final options = PlanOptions(
          excludedFoods: excluded,
          vegetarian: veggie == 'true',
          maxMinutes: query['max_minutes'] == null
              ? null
              : int.parse(query['max_minutes']!),
        );
        planner.validate(recipes, options);
        final found = recipes
            .where(
              (r) =>
                  planner.matches(r, options) &&
                  (ids.isEmpty ||
                      (mode == 'all'
                          ? r.foodIds.containsAll(ids)
                          : r.foodIds.intersection(ids).isNotEmpty)) &&
                  (query['q'] == null ||
                      r.title.toLowerCase().contains(
                            query['q']!.toLowerCase(),
                          )) &&
                  (query['meal_type'] == null ||
                      r.mealTypes.contains(query['meal_type'])),
            )
            .toList();
        output = {
          'total': found.length,
          'items': found.skip(offset).take(limit).map((r) => r.source).toList(),
        };
      } else if (request.method == 'GET' &&
          RegExp(r'^/recipes/bm-\d{3}$').hasMatch(path)) {
        final recipe = index[path.split('/').last];
        if (recipe == null) {
          response.statusCode = 404;
          output = {'error': 'recipe_not_found'};
        } else {
          output = recipe.source;
        }
      } else if (request.method == 'GET' &&
          RegExp(r'^/photos/bm-\d{3}\.jpg$').hasMatch(path)) {
        final recipe = index[path.split('/').last.replaceAll('.jpg', '')];
        if (recipe == null) {
          response.statusCode = 404;
          output = {'error': 'photo_not_found'};
        } else {
          response.headers.contentType = ContentType('image', 'jpeg');
          response.add(await File(recipe.photoAsset).readAsBytes());
          continue;
        }
      } else if (request.method == 'POST' && path == '/plans') {
        if (request.headers.contentType?.mimeType != 'application/json') {
          response.statusCode = 415;
          output = {'error': 'Content-Type application/json requis.'};
        } else {
          final bytes = <int>[];
          await for (final chunk in request.timeout(
            const Duration(seconds: 10),
          )) {
            bytes.addAll(chunk);
            if (bytes.length > 65536) {
              throw ArgumentError('Corps trop volumineux.');
            }
          }
          final json = jsonDecode(utf8.decode(bytes));
          if (json is! Map<String, dynamic>) {
            throw ArgumentError('Objet JSON requis.');
          }
          final defaults = PlanOptions().toJson();
          if (json.keys.any((key) => !defaults.containsKey(key))) {
            throw ArgumentError('Champ inconnu.');
          }
          final plan = planner.generate(
            recipes,
            PlanOptions.fromJson({...defaults, ...json}),
          );
          final file = File('${directory.path}/${plan.id}.json');
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsString(jsonEncode(plan.toJson()), flush: true);
          await temporary.rename(file.path);
          response.statusCode = 201;
          output = planJson(plan, planner.shoppingList(plan, recipes));
        }
      } else if (request.method == 'GET' &&
          RegExp(r'^/plans/[0-9]+-[0-9]+(?:/shopping-list)?$').hasMatch(path)) {
        final file = File('${directory.path}/${path.split('/')[2]}.json');
        if (!await file.exists()) {
          response.statusCode = 404;
          output = {'error': 'plan_not_found'};
        } else {
          final plan = MealPlan.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>,
          );
          final shopping = planner.shoppingList(plan, recipes);
          output = path.endsWith('/shopping-list')
              ? shoppingJson(shopping)
              : planJson(plan, shopping);
        }
      } else {
        response.statusCode = 404;
        output = {'error': 'not_found'};
      }
      response.write(jsonEncode(output));
    } on ArgumentError catch (e) {
      response.statusCode = 400;
      response.write(jsonEncode({'error': '${e.message}'}));
    } on FormatException catch (e) {
      response.statusCode = 400;
      response.write(jsonEncode({'error': e.message}));
    } on TypeError {
      response.statusCode = 400;
      response.write(jsonEncode({'error': 'Type de champ invalide.'}));
    } catch (error) {
      response.statusCode = 500;
      response.write(jsonEncode({'error': 'internal_error'}));
      stderr.writeln(error);
    } finally {
      await response.close();
    }
  }
}

Map<String, dynamic> shoppingJson(ShoppingList shopping) => {
      'items': shopping.items
          .map(
            (i) => {
              'description': i.description,
              'quantity': i.quantity,
              'unit': i.unit,
              'group': i.group,
            },
          )
          .toList(),
      'manual_items': shopping.manualItems,
    };
Map<String, dynamic> planJson(MealPlan plan, ShoppingList shopping) => {
      ...plan.toJson(),
      'complete': plan.complete,
      'shopping_list': shoppingJson(shopping),
    };
