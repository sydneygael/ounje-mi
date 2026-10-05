import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ounje_mi/data/recipe_repository.dart';
import 'package:ounje_mi/domain/planner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('le repository charge les 146 recettes embarquées', () async {
    final repository = LocalRecipeRepository();
    expect((await repository.loadRecipes()).length, 146);
    expect(await repository.loadPlan(), isNull);
  });
  test(
    'le dernier planning survit à une nouvelle instance du repository',
    () async {
      final repository = LocalRecipeRepository();
      final recipes = await repository.loadRecipes();
      final plan = const WeeklyPlanner().generate(recipes, PlanOptions());
      await repository.savePlan(plan);
      final restored = await LocalRecipeRepository().loadPlan();
      expect(restored?.toJson(), plan.toJson());
    },
  );
}
