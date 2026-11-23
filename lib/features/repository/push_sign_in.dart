import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../access/forge/device_flow.dart';
import '../../access/forge/forge_http.dart';
import '../../contracts/clones.dart';
import '../../engines/remote_url.dart';
import '../../managers/repositories_manager.dart';
import '../repositories/providers.dart';
import '../repositories/sign_in_sheet.dart';

/// After the remote refused to let this clone push: a token for its host,
/// kept in the keychain, or signing in with the forge where an OAuth app is
/// set up. True once one is saved; the clone uses it from then on.
Future<bool> signInToPush(
  BuildContext context,
  WidgetRef ref,
  CloneRecord record,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PushSignInSheet(record: record),
  );
  if (saved != true) return false;
  ref.invalidate(clonesProvider);
  return true;
}

class _PushSignInSheet extends ConsumerStatefulWidget {
  const _PushSignInSheet({required this.record});

  final CloneRecord record;

  @override
  ConsumerState<_PushSignInSheet> createState() => _PushSignInSheetState();
}

class _PushSignInSheetState extends ConsumerState<_PushSignInSheet> {
  final _token = TextEditingController();
  final _flow = DeviceFlow(IoForgeHttp());
  var _busy = false;

  late final _repository = parseRemote(widget.record.url);
  String get _host => _repository?.host ?? widget.record.url;

  Forge? get _forge => switch (_host.toLowerCase()) {
    'github.com' => Forge.github,
    'gitlab.com' => Forge.gitlab,
    _ => null,
  };

  /// Where the forge makes tokens, for the ones Genbeya knows.
  Uri? get _tokenPage => switch (_forge) {
    Forge.github => Uri.parse(
      'https://github.com/settings/personal-access-tokens/new',
    ),
    Forge.gitlab => Uri.parse(
      'https://gitlab.com/-/user_settings/personal_access_tokens',
    ),
    null => null,
  };

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save(String token) async {
    setState(() => _busy = true);
    final manager = await ref.read(repositoriesManagerProvider.future);
    await manager.saveToken(_host, RepositoriesManager.tokenUser(_host), token);
    if (widget.record.credential == CredentialKind.none) {
      await manager.setCredential(widget.record.id, CredentialKind.token);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _signIn(Forge forge) async {
    final account = await showModalBottomSheet<ForgeAccount>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SignInSheet(flow: _flow, forge: forge),
    );
    if (account != null && mounted) await _save(account.token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forge = _forge;
    final page = _tokenPage;
    final repository = _repository;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign in to push', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              widget.record.credential == CredentialKind.none
                  ? 'This clone reads $_host without signing in, which is enough for a public repository. '
                        'Pushing needs a token that may write to ${repository?.path ?? 'it'}.'
                  : '$_host refused the token kept for it. It may have expired, or not allow writing to ${repository?.path ?? 'this repository'}.',
            ),
            const SizedBox(height: 12),
            if (forge != null && _flow.offers(forge)) ...[
              FilledButton.icon(
                onPressed: _busy ? null : () => _signIn(forge),
                icon: const Icon(Icons.login),
                label: Text(
                  'Sign in with ${forge == Forge.github ? 'GitHub' : 'GitLab'}',
                ),
              ),
              const SizedBox(height: 12),
              const Text('Or enter a token:'),
            ],
            TextField(
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Token for $_host',
                helperText:
                    'Kept in this phone\'s keychain, sent only to $_host.',
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) _save(value.trim());
              },
            ),
            if (page != null)
              TextButton.icon(
                onPressed: () =>
                    launchUrl(page, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  forge == Forge.github
                      ? 'Make one on GitHub: this repository, Contents read and write'
                      : 'Make one on GitLab: scope write_repository',
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        final token = _token.text.trim();
                        if (token.isNotEmpty) _save(token);
                      },
                child: const Text('Save and sync'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
