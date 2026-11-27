import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../engines/remote_url.dart';
import '../../managers/repository_session.dart';
import 'work_provider.dart';

/// How many commits "More" fetches.
const olderStep = 200;

/// Where a task's activity ends at a shallow clone's edge ([[GM-29]]): says
/// so and offers to fetch older history, saying how much and from where;
/// [onFetched] then shows the activity again.
class OlderHistory extends ConsumerStatefulWidget {
  const OlderHistory({
    super.key,
    required this.session,
    required this.onFetched,
  });

  final RepositorySession session;
  final VoidCallback onFetched;

  @override
  ConsumerState<OlderHistory> createState() => _OlderHistoryState();
}

class _OlderHistoryState extends ConsumerState<OlderHistory> {
  var _busy = false;
  String? _problem;

  String get _host {
    final url = widget.session.record?.url ?? '';
    return parseRemote(url)?.host ?? url;
  }

  Future<void> _ask() async {
    final more = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fetch older history?'),
        content: Text(
          'This phone keeps only the newest commits, to clone quickly. Older ones are '
          'on $_host. "$olderStep more" fetches the next $olderStep commits; "All of it" '
          'the whole history, which can be large. Either downloads over the network '
          'the phone is on now, mobile data too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('All of it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, olderStep),
            child: const Text('$olderStep more'),
          ),
        ],
      ),
    );
    if (more == null || !mounted) return;
    await _fetch(more == 0 ? null : more);
  }

  Future<void> _fetch(int? more) async {
    final record = widget.session.record!;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final work = await ref.read(workProvider(record).future);
      await work.sync.fetchOlder(more: more);
      await widget.session.load();
      widget.onFetched();
    } on Object catch (error) {
      if (mounted) setState(() => _problem = "Couldn't fetch: $error");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canFetch = widget.session.record != null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Older history isn't on this phone: the clone is shallow.",
          ),
          if (_problem case final problem?) ...[
            const SizedBox(height: 8),
            Text(
              problem,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (canFetch) ...[
            const SizedBox(height: 8),
            if (_busy) ...[
              Text('Fetching from $_host…'),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ] else
              OutlinedButton.icon(
                onPressed: _ask,
                icon: const Icon(Icons.history),
                label: const Text('Fetch older history'),
              ),
          ],
        ],
      ),
    );
  }
}
