/// Changing wiki pages from the phone: for now the checkboxes on them
/// ([[Call chains#c5-render-a-page]]). Pages are written in full with
/// [[GM-16]]. Commits are named as desktop names a file save, `Edit <path>`.
library;

import '../access/kit/kit_host.dart';
import '../engines/checkbox_engine.dart';
import 'content_writer.dart';
import 'repository_model.dart';
import 'repository_session.dart';
import 'task_writer.dart';

class PageWriter {
  PageWriter({required this.session, required this.writer});

  final RepositorySession session;
  final ContentWriter writer;

  /// [page] with the checkbox ticked whose task list item starts at
  /// [offset] in the rendered page; null when no item starts there. Throws
  /// [ChangedMeanwhileException] when the page changed since it was shown.
  Future<KitPage?> toggle(KitPage page, int offset) async {
    final original = await session.readText(page.path);
    if (fileHash(original) != page.hash) {
      throw const ChangedMeanwhileException(
        'This page changed meanwhile. Open it again to see the latest version.',
      );
    }
    final content = togglePageCheckbox(original, offset);
    if (content == null) return null;
    await writer.write(session.state!, {
      page.path: content,
    }, 'Edit ${page.path}');
    await session.load();
    return session.page(page.path);
  }
}
