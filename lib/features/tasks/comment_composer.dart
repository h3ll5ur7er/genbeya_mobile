import 'package:material_ui/material_ui.dart';

import '../../contracts/model.dart';
import '../../managers/repository_model.dart';
import '../../managers/search.dart';
import '../../managers/suggestions.dart';
import '../repository/links.dart';
import 'task_look.dart';
import 'task_pickers.dart';

/// The comment box above the keyboard (D4: a native field, the app's own
/// pickers): `@` for people, `[[` for tasks, pages and files, `//` for
/// dates, offered as desktop's editor offers them while typing, and as
/// buttons. [onSend] writes the comment and says whether it did; the field
/// empties then. With [editing], it changes that comment instead.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.state,
    required this.onSend,
    this.editing,
    this.onCancelEdit,
  });

  final RepositoryState state;
  final Future<bool> Function(String text) onSend;

  /// The text of the comment being edited, if one is.
  final String? editing;
  final VoidCallback? onCancelEdit;

  @override
  State<CommentComposer> createState() => CommentComposerState();
}

/// A suggestion as the list shows it, and the text that picking it puts
/// in place of the trigger and the query.
typedef _Suggestion = ({
  Widget leading,
  String label,
  String? detail,
  Future<String?> Function(String next) insert,
});

class CommentComposerState extends State<CommentComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _sending = false;

  /// The trigger and query before the cursor: where they start, and the list.
  ({int start, List<_Suggestion> items})? _open;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    // The picker buttons show while the field has focus.
    _focus.addListener(() => setState(() {}));
    if (widget.editing != null) _text.text = widget.editing!;
  }

  @override
  void didUpdateWidget(CommentComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing != oldWidget.editing) {
      _text.text = widget.editing ?? '';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
      if (widget.editing != null) _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Focuses the field, as answering does.
  void focus() => _focus.requestFocus();

  String get _before {
    final cursor = _text.selection.baseOffset;
    if (cursor < 0 || cursor > _text.text.length) return '';
    return _text.text.substring(0, cursor);
  }

  void _changed() {
    final before = _before;
    final open = _suggestionsFor(before);
    if (open != null || _open != null) setState(() => _open = open);
  }

  ({int start, List<_Suggestion> items})? _suggestionsFor(String before) {
    final line = before.substring(before.lastIndexOf('\n') + 1);
    final lineStart = before.length - line.length;
    if (referenceTrigger.firstMatch(line) case final match?) {
      final query = match[1]!;
      return (start: lineStart + match.start + 2, items: _references(query));
    }
    if (dateTrigger.firstMatch(before) case final match?) {
      return (start: match.start, items: _dates(match[1]!));
    }
    if (mentionTrigger.firstMatch(before) case final match?) {
      return (start: match.start, items: _mentions(match[1]!));
    }
    return null;
  }

  List<_Suggestion> _mentions(String query) => [
    for (final person in mentionSuggestions(widget.state.people, query))
      (
        leading: PersonAvatar(name: person.name, size: 28),
        label: person.name,
        detail: '@${person.handle}',
        insert: (next) async => mentionText(person, next),
      ),
  ];

  List<_Suggestion> _references(String query) {
    final state = widget.state;
    final pages = [
      for (final path in wikiPages(state.wiki))
        (path: path, title: _titleOf(state.wiki, path) ?? path),
    ];
    final candidates = referenceCandidates(
      tasks: state.tasks,
      pages: pages,
      files: [for (final f in state.codeFiles) f.path],
      wikiRoot: state.settings.wikiRoot,
    );
    final text = query.trim();
    final ranked = text.isEmpty
        ? [
            for (final c in candidates)
              if (c.kind != 'file') (c, 0.0),
          ]
        : [
            for (final c in candidates)
              if (fuzzyScore(c.label, text) case final score when score >= 0)
                (c, score),
          ];
    if (text.isNotEmpty) ranked.sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (c, _) in ranked.take(30))
        (
          leading: Icon(switch (c.kind) {
            'task' => Icons.task_alt,
            'page' => Icons.article_outlined,
            _ => Icons.description_outlined,
          }, size: 22),
          label: c.label,
          detail: c.detail,
          insert: (next) async => referenceText(c, next),
        ),
    ];
  }

  static String? _titleOf(List<WikiNode> nodes, String path) {
    for (final node in nodes) {
      if (node.path == path) return node.title;
      final found = _titleOf(node.children, path);
      if (found != null) return found;
    }
    return null;
  }

  List<_Suggestion> _dates(String query) {
    final localizations = MaterialLocalizations.of(context);
    String format(String iso) =>
        localizations.formatFullDate(DateTime.parse(iso));
    return [
      for (final s in dateSuggestions(query, todayIso(), formatDate: format))
        (
          leading: Icon(
            s.date == null ? Icons.calendar_month : Icons.event,
            size: 22,
          ),
          label: s.label,
          detail: s.date == null ? null : format(s.date!),
          insert: (next) async {
            if (s.date != null) return s.date;
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(1000),
              lastDate: DateTime(9999, 12, 31),
            );
            return picked == null ? null : dateText(picked);
          },
        ),
    ];
  }

  /// Puts what [suggestion] inserts in place of the trigger and its query.
  Future<void> _pick(_Suggestion suggestion) async {
    final open = _open;
    if (open == null) return;
    final cursor = _text.selection.baseOffset;
    final text = _text.text;
    final next = text.substring(cursor);
    final insert = await suggestion.insert(next);
    if (insert == null || !mounted) return;
    // A reference keeps its `[[`; mentions and dates replace their trigger.
    final updated = text.replaceRange(open.start, cursor, insert);
    final end =
        open.start +
        insert.length +
        (insert.endsWith(']]') || !next.startsWith(']]') ? 0 : 2);
    _text.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: end),
    );
    _focus.requestFocus();
  }

  /// A picker button: its trigger at the cursor, opening its suggestions.
  void _trigger(String trigger) {
    final selection = _text.selection;
    final text = _text.text;
    final at = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before = text.substring(0, at);
    final spaced = before.isEmpty || RegExp(r'\s$').hasMatch(before) ? '' : ' ';
    final insert = '$spaced$trigger';
    _text.value = TextEditingValue(
      text: text.replaceRange(at, end, insert),
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    final sent = await widget.onSend(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) {
      _text.clear();
      _focus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = _open;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (open != null && open.items.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final item in open.items)
                      ListTile(
                        dense: true,
                        leading: item.leading,
                        title: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.detail == null
                            ? null
                            : Text(item.detail!),
                        onTap: () => _pick(item),
                      ),
                  ],
                ),
              ),
            if (widget.editing != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.edit_outlined, size: 20),
                title: const Text('Editing your comment'),
                trailing: IconButton(
                  tooltip: 'Stop editing',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _text.clear();
                    widget.onCancelEdit?.call();
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: widget.editing != null
                            ? 'Your comment'
                            : 'Add a comment…',
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.editing != null ? 'Save' : 'Send',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            widget.editing != null ? Icons.check : Icons.send,
                          ),
                  ),
                ],
              ),
            ),
            if (_focus.hasFocus)
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    for (final (trigger, tooltip) in const [
                      ('@', 'Mention someone'),
                      ('[[', 'Refer to a task, page or file'),
                      ('//', 'A date'),
                    ])
                      TextButton(
                        onPressed: () => _trigger(trigger),
                        child: Text(trigger, semanticsLabel: tooltip),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
