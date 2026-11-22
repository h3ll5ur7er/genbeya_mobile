import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../engines/search_engine.dart';
import '../../managers/repository_session.dart';
import '../../managers/search.dart';
import 'links.dart';
import 'task_view_screen.dart';
import 'wiki_screen.dart';

/// Search, from the top bar of every screen ([[Experience#search]]): pages,
/// tasks and files by name as you type, the text of everything below.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.session});

  final RepositorySession session;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _text = TextEditingController();
  final _engine = SearchEngine();
  var _caseSensitive = false;
  var _wholeWord = false;
  var _regex = false;
  List<NameHit> _names = const [];
  ContentResults? _results;
  String? _problem;
  var _searching = false;
  Timer? _debounce;
  var _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    final text = _text.text;
    setState(() {
      _names = searchNames(widget.session.state!, text);
      _problem = null;
    });
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _searchText);
  }

  Future<void> _searchText() async {
    final generation = ++_generation;
    final SearchQuery query;
    try {
      query = _engine.validate(
        _text.text,
        caseSensitive: _caseSensitive,
        regex: _regex,
        wholeWord: _wholeWord,
      );
    } on SearchException catch (error) {
      setState(() => _problem = error.message);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await widget.session.search(query);
      if (mounted && generation == _generation) {
        setState(() => _results = results);
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _problem = '$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  void _open(String path) {
    final state = widget.session.state!;
    switch (fileTarget(state, path)) {
      case FileTarget.task:
        final task = state.tasks.firstWhere((t) => t.path == path);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TaskViewScreen(session: widget.session, task: task),
          ),
        );
      case FileTarget.page:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                WikiScreen(session: widget.session, initialPage: path),
          ),
        );
      case FileTarget.file:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$path: files open in Code, which comes with GM-17.'),
          ),
        );
    }
  }

  Widget _toggle(String tooltip, IconData icon, bool on, VoidCallback flip) =>
      IconButton(
        tooltip: tooltip,
        isSelected: on,
        icon: Icon(icon),
        onPressed: () {
          flip();
          _changed();
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _text,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Pages, tasks, files and their text',
            border: InputBorder.none,
          ),
          onChanged: (_) => _changed(),
        ),
        actions: [
          _toggle(
            'Match case',
            Icons.text_fields,
            _caseSensitive,
            () => _caseSensitive = !_caseSensitive,
          ),
          _toggle(
            'Whole word',
            Icons.space_bar,
            _wholeWord,
            () => _wholeWord = !_wholeWord,
          ),
          _toggle(
            'Regular expression',
            Icons.code,
            _regex,
            () => _regex = !_regex,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          for (final kind in SearchKind.values)
            if (_names.any((n) => n.kind == kind)) ...[
              _Heading(switch (kind) {
                SearchKind.page => 'Pages',
                SearchKind.task => 'Tasks',
                SearchKind.file => 'Files',
              }),
              for (final hit in _names.where((n) => n.kind == kind))
                ListTile(
                  dense: true,
                  leading: Icon(switch (kind) {
                    SearchKind.page => Icons.description_outlined,
                    SearchKind.task => Icons.task_alt,
                    SearchKind.file => Icons.insert_drive_file_outlined,
                  }),
                  title: Text(hit.title),
                  subtitle: Text(hit.detail),
                  onTap: () => _open(hit.path),
                ),
            ],
          if (_searching) const LinearProgressIndicator(),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _problem!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (results != null) ...[
            for (final (label, hits) in [
              ('In pages', results.wiki),
              ('In tasks', results.tasks),
              ('In pull requests', results.pulls),
              ('In code', results.code),
            ])
              if (hits.isNotEmpty) ...[
                _Heading(label),
                for (final hit in hits)
                  _ContentHitView(hit: hit, onTap: () => _open(hit.path)),
              ],
            if (results.truncated)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'More matched than is listed; search for something more specific.',
                ),
              ),
            if ([
                  results.wiki,
                  results.tasks,
                  results.pulls,
                  results.code,
                ].every((h) => h.isEmpty) &&
                _names.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No matches.'),
              ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ContentHitView extends StatelessWidget {
  const _ContentHitView({required this.hit, required this.onTap});
  final ContentHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faint = TextStyle(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 12,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hit.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(hit.detail, style: faint),
            for (final match in hit.matches) ...[
              const SizedBox(height: 4),
              if (match.before != null && match.before!.trim().isNotEmpty)
                Text(
                  '${match.line - 1}  ${match.before!.trim()}',
                  style: faint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${match.line}  ', style: faint),
                    ..._marked(match.text, match.ranges, theme),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (match.after != null && match.after!.trim().isNotEmpty)
                Text(
                  '${match.line + 1}  ${match.after!.trim()}',
                  style: faint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ],
        ),
      ),
    );
  }

  static List<TextSpan> _marked(
    String text,
    List<SearchRange> ranges,
    ThemeData theme,
  ) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final range in ranges) {
      if (range.start < at || range.end > text.length) continue;
      if (range.start > at) {
        spans.add(TextSpan(text: text.substring(at, range.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: TextStyle(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.25),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      at = range.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }
}
