import 'package:flutter/material.dart';

import 'data/recipe_repository.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(OunjeMiApp(repository: LocalRecipeRepository()));
}

class OunjeMiApp extends StatelessWidget {
  const OunjeMiApp({super.key, required this.repository});
  final RecipeRepository repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ounjé Mi',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315F42)),
          scaffoldBackgroundColor: const Color(0xFFF8F7F2),
        ),
        home: HomeScreen(repository: repository),
      );
}
