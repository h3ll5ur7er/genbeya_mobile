import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'features/links/open_link.dart';
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
  }

  void _open(String link) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = router.routerDelegate.navigatorKey.currentState;
      if (navigator != null && mounted) {
        unawaited(openGenbeyaLink(navigator, ref, link));
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
