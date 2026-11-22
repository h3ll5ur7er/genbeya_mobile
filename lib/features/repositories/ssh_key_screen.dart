import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'providers.dart';

final _deviceKeyProvider = FutureProvider((ref) async {
  final manager = await ref.watch(repositoriesManagerProvider.future);
  return manager.deviceKey();
});

/// This phone's SSH key: made on the phone, the private half never leaves
/// its keychain; the public half goes to the forge account.
class SshKeyScreen extends ConsumerWidget {
  const SshKeyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ref.watch(_deviceKeyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('SSH key of this phone')),
      body: key.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text("Couldn't make the key: $error"),
        ),
        data: (key) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Add this public key to your account on the server (on GitHub: Settings → SSH and GPG keys → New SSH key). '
              'The private key was made on this phone and stays in its keychain.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              key.publicKey,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text('Fingerprint: ${key.fingerprint}'),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: key.publicKey));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Public key copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy public key'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
