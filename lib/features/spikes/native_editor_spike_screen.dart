import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import 'editor_samples.dart';
import 'editor_toolbar.dart';

/// GM-4's comparison: a native Flutter editor (re_editor) on the same text,
/// with the same toolbar, but no completions.
class NativeEditorSpikeScreen extends StatefulWidget {
  const NativeEditorSpikeScreen({super.key});

  @override
  State<NativeEditorSpikeScreen> createState() =>
      _NativeEditorSpikeScreenState();
}

class _NativeEditorSpikeScreenState extends State<NativeEditorSpikeScreen> {
  final _controller = CodeLineEditingController.fromText(shortSample);
  bool _long = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _wrap(String marker) =>
      _controller.replaceSelection('$marker${_controller.selectedText}$marker');

  void _command(String command) {
    switch (command) {
      case 'bold':
        _wrap('**');
      case 'italic':
        _wrap('_');
      case 'heading':
        _controller.replaceSelection('## ${_controller.selectedText}');
      case 'list':
        _controller.replaceSelection('- ${_controller.selectedText}');
      case 'checkbox':
        _controller.replaceSelection('- [ ] ${_controller.selectedText}');
      case 'undo':
        _controller.undo();
      case 'redo':
        _controller.redo();
      default:
        if (command.startsWith('insert:')) {
          _controller.replaceSelection(command.substring(7));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor (native)'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _long = !_long;
              _controller.text = _long ? longSample() : shortSample;
            }),
            child: Text(_long ? 'Short page' : '2,000 lines'),
          ),
        ],
      ),
      // The toolbar stays above Android's navigation bar.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: CodeEditor(
                controller: _controller,
                wordWrap: true,
                style: CodeEditorStyle(
                  fontSize: 15,
                  // Plain text takes these, not the highlight theme's colours.
                  textColor: scheme.onSurface,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  cursorColor: scheme.primary,
                  selectionColor: scheme.primary.withValues(alpha: 0.3),
                  cursorLineColor: scheme.onSurface.withValues(alpha: 0.05),
                  codeTheme: CodeHighlightTheme(
                    languages: {
                      'markdown': CodeHighlightThemeMode(mode: langMarkdown),
                    },
                    theme: dark ? atomOneDarkTheme : atomOneLightTheme,
                  ),
                ),
              ),
            ),
            EditorToolbar(onCommand: _command),
          ],
        ),
      ),
    );
  }
}
