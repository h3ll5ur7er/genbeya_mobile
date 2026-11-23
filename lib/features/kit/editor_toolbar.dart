import 'package:material_ui/material_ui.dart';

/// The row above the keyboard of the kit editor: formatting, references, mentions.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.onCommand});

  /// `bold`, `italic`, `heading`, `list`, `checkbox`, `link`, `undo`, `redo`,
  /// or `insert:<text>`.
  final void Function(String command) onCommand;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, String command, {String? tooltip}) =>
        TextButton(
          onPressed: () => onCommand(command),
          child: Text(label, semanticsLabel: tooltip ?? label),
        );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            button('H', 'heading', tooltip: 'Heading'),
            button('B', 'bold', tooltip: 'Bold'),
            button('I', 'italic', tooltip: 'Italic'),
            button('•', 'list', tooltip: 'List'),
            button('☐', 'checkbox', tooltip: 'Checkbox'),
            button('[[', 'insert:[[', tooltip: 'Reference'),
            button('@', 'insert:@', tooltip: 'Mention'),
            button('//', 'insert://', tooltip: 'Date'),
            button('↶', 'undo', tooltip: 'Undo'),
            button('↷', 'redo', tooltip: 'Redo'),
          ],
        ),
      ),
    );
  }
}
