import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_host.dart';
import '../../contracts/clones.dart';
import '../../contracts/model.dart';
import '../../managers/repository_session.dart';
import '../kit/editor_toolbar.dart';
import '../kit/kit_view.dart';
import 'task_editing.dart';

/// A task's title and description, edited: the title in a native field,
/// the description in the kit's editor with Genbeya's completions (D4).
/// Saving writes both as one commit; the task returned is the saved one.
class TaskEditScreen extends ConsumerStatefulWidget {
  const TaskEditScreen({
    super.key,
    required this.record,
    required this.session,
    required this.task,
  });

  final CloneRecord record;
  final RepositorySession session;
  final Task task;

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  late final KitHost _host;
  late final _title = TextEditingController(text: widget.task.title);
  var _dirty = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
    _host = KitHost(
      files: widget.session.kitFiles(),
      onEditorState: (state) {
        if (state.dirty != _dirty) setState(() => _dirty = state.dirty);
      },
      onSave: (_, text) => _save(text),
    )..updateContext(widget.session.kitContext());
    _host.edit(
      KitEdit(
        area: 'tasks',
        path: widget.task.path,
        text: widget.task.body,
        hash: widget.task.hash,
      ),
    );
  }

  void _changed() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.setTheme(dark: Theme.of(context).brightness == Brightness.dark);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _changedAny => _dirty || _title.text != widget.task.title;

  Future<void> _save(String body) async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the task a title first.')),
      );
      return;
    }
    setState(() => _saving = true);
    final saved = await changeTask(
      context,
      ref,
      widget.record,
      widget.session,
      (tasks) => tasks.update(
        widget.task,
        widget.task.toInput().copyWith(title: _title.text, body: body),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) Navigator.of(context).pop(saved);
  }

  Future<bool> _discard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard your changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;

  void _command(String command) => command.startsWith('insert:')
      ? _host.command('insert', text: command.substring(7))
      : _host.command(command);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_changedAny || _saving,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _discard() && context.mounted) Navigator.of(context).pop();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.task.id}'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  // The kit answers with the text, which [_save] writes.
                  onPressed: _changedAny ? () => _host.command('save') : null,
                  child: const Text('Save'),
                ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: KitView(host: _host)),
            EditorToolbar(onCommand: _command),
          ],
        ),
      ),
    ),
  );
}
