import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quick_actions/quick_actions.dart';

import 'features/links/open_link.dart';
import 'features/links/shared_text.dart';
import 'features/tasks/start_new_task.dart';
import 'managers/web_links.dart';
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

class GenbeyaApp extends ConsumerStatefulWidget {
  const GenbeyaApp({super.key, this.listenForLinks = true});

  /// Whether Genbeya links from the system open in the app (off in tests).
  final bool listenForLinks;

  @override
  ConsumerState<GenbeyaApp> createState() => _GenbeyaAppState();
}

class _GenbeyaAppState extends ConsumerState<GenbeyaApp> {
  StreamSubscription<String>? _links;

  @override
  void initState() {
    super.initState();
    if (widget.listenForLinks) unawaited(_listen());
  }

  /// Links that started the app, and those that arrive while it runs.
  Future<void> _listen() async {
    try {
      final links = AppLinks();
      _links = links.stringLinkStream.listen(_open, onError: (Object _) {});
      final first = await links.getInitialLinkString();
      if (first != null) _open(first);
    } on Object {
      // No link handling on this platform.
    }
    await SharedText.listen(_shared);
    await _shortcuts();
  }

  /// Text shared into the app: the link in it opens; text without one
  /// becomes a new task ([[GM-12]]).
  void _shared(String text) {
    final link = firstLink(text);
    if (link != null) return _open(link);
    _withNavigator((navigator) => startNewTask(navigator, ref, text: text));
  }

  /// The app icon's shortcuts: **New task**.
  Future<void> _shortcuts() async {
    try {
      const actions = QuickActions();
      await actions.initialize((type) {
        if (type == 'new_task') {
          _withNavigator((navigator) => startNewTask(navigator, ref));
        }
      });
      await actions.setShortcutItems(const [
        ShortcutItem(
          type: 'new_task',
          localizedTitle: 'New task',
          icon: 'ic_shortcut_new_task',
        ),
      ]);
    } on Object {
      // No shortcuts on this platform.
    }
  }

  void _withNavigator(Future<void> Function(NavigatorState navigator) run) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = router.routerDelegate.navigatorKey.currentState;
      if (navigator != null && mounted) unawaited(run(navigator));
    });
  }

  void _open(String link) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = router.routerDelegate.navigatorKey.currentState;
      if (navigator != null && mounted) {
        unawaited(openLinkText(navigator, ref, link));
      }
    });
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

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
