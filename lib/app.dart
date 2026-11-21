import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'features/repositories/repositories_screen.dart';
import 'features/spikes/spikes_screen.dart';
import 'features/theme/genbeya_theme.dart';

/// The app's routes. Screens are added here as the features arrive.
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const RepositoriesScreen()),
    GoRoute(path: '/spikes', builder: (context, state) => const SpikesScreen()),
  ],
);

class GenbeyaApp extends StatelessWidget {
  const GenbeyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Genbeya Mobile',
      theme: GenbeyaTheme.light(),
      darkTheme: GenbeyaTheme.dark(),
      routerConfig: router,
    );
  }
}
