import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';

/// Asks for the name and email a clone's commits are signed with.
Future<GitIdentity?> showIdentityDialog(
  BuildContext context,
  GitIdentity? current,
) {
  final name = TextEditingController(text: current?.name ?? '');
  final email = TextEditingController(text: current?.email ?? '');
  return showDialog<GitIdentity>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Git name and email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Commits from this phone are signed with these, and "me" on Today is who they name.',
          ),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.words,
          ),
          TextField(
            controller: email,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            name: name.text.trim(),
            email: email.text.trim(),
          )),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
