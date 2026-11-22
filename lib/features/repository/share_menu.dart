import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../engines/genbeya_link.dart';
import '../../managers/repository_session.dart';

/// **Share Genbeya link** and **Share web link**, through the system's share
/// sheet ([[Experience#sharing-and-links]]).
class ShareMenu extends StatelessWidget {
  const ShareMenu({
    super.key,
    required this.session,
    required this.item,
    required this.path,
  });

  final RepositorySession session;
  final LinkItem item;

  /// The file the web link shows.
  final String path;

  @override
  Widget build(BuildContext context) {
    final genbeya = session.genbeyaLink(item);
    final web = session.webLink(path);
    return PopupMenuButton<String>(
      tooltip: 'Share',
      icon: const Icon(Icons.share_outlined),
      onSelected: (link) => SharePlus.instance.share(ShareParams(text: link)),
      itemBuilder: (_) => [
        if (genbeya != null)
          PopupMenuItem(
            value: genbeya,
            child: const Text('Share Genbeya link'),
          ),
        if (web != null)
          PopupMenuItem(value: web, child: const Text('Share web link')),
      ],
    );
  }
}
