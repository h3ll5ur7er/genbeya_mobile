import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';
import '../repositories/repository_screen.dart';
import '../tasks/tasks_screen.dart';
import 'session_provider.dart';
import 'wiki_screen.dart';

/// Inside a repository: a bottom bar of its parts ([[Experience#navigation]]).
/// Today, pull requests and code join as they arrive.
class RepositoryShell extends ConsumerStatefulWidget {
  const RepositoryShell({super.key, required this.record});

  final CloneRecord record;

  @override
  ConsumerState<RepositoryShell> createState() => _RepositoryShellState();
}

class _RepositoryShellState extends ConsumerState<RepositoryShell> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider(widget.record));
    return session.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(widget.record.name)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(widget.record.name)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text("Couldn't read the repository: $error"),
        ),
      ),
      data: (session) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            WikiScreen(record: widget.record, session: session),
            TasksScreen(session: session),
            RepositoryScreen(record: widget.record),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (tab) => setState(() => _tab = tab),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Wiki',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_kanban_outlined),
              label: 'Tasks',
            ),
            NavigationDestination(
              icon: Icon(Icons.info_outline),
              label: 'About',
            ),
          ],
        ),
      ),
    );
  }
}
