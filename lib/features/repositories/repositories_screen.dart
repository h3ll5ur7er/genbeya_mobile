import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The start screen: the clones on this phone. Empty until cloning exists (GM-6).
class RepositoriesScreen extends StatelessWidget {
  const RepositoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Repositories')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No repositories yet', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Cloning comes with GM-6. Until then, the spikes try what the app is built on.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.push('/spikes'),
                child: const Text('Open the spikes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
