import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../access/forge/device_flow.dart';
import '../../access/forge/forge_http.dart';
import '../../access/git/git_remote.dart';
import '../../contracts/clones.dart';
import '../../engines/remote_url.dart';
import '../../managers/repositories_manager.dart';
import 'format.dart';
import 'providers.dart';
import 'sign_in_sheet.dart';

/// Adds a clone: the address, how the phone reaches it, then which branch,
/// how deep and who commits are signed as; cloning shows progress and can
/// be cancelled (US-1, US-3).
class AddRepositoryScreen extends ConsumerStatefulWidget {
  const AddRepositoryScreen({super.key});

  @override
  ConsumerState<AddRepositoryScreen> createState() =>
      _AddRepositoryScreenState();
}

enum _Access { public, token }

class _AddRepositoryScreenState extends ConsumerState<AddRepositoryScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  var _access = _Access.public;
  String? _savedTokenHost;
  String? _publicKey;
  RemotePlan? _plan;
  String? _branch;
  var _fullHistory = false;
  var _busy = false;
  String? _problem;
  int? _operation;
  CloneProgress? _progress;

  RepositoriesManager? _manager;
  final _flow = DeviceFlow(IoForgeHttp());
  ForgeAccount? _account;
  List<ForgeRepository>? _repositories;

  @override
  void initState() {
    super.initState();
    _url.addListener(_urlChanged);
    ref.read(repositoriesManagerProvider.future).then((manager) async {
      _manager = manager;
      final last = await manager.lastIdentity();
      if (!mounted || last == null) return;
      _name.text = last.name;
      _email.text = last.email;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _isSsh {
    final text = _url.text.trim().toLowerCase();
    return RegExp(r'^(ssh|git\+ssh|ssh\+git)://').hasMatch(text) ||
        (!text.contains('://') && parseRemote(text) != null);
  }

  Future<void> _urlChanged() async {
    final manager = _manager;
    final repository = parseRemote(_url.text);
    setState(() {
      _plan = null;
      _problem = null;
    });
    if (manager == null || repository == null) return;
    if (_isSsh) {
      final key = await manager.deviceKey();
      if (mounted) setState(() => _publicKey = key.publicKey);
      return;
    }
    final saved = await manager.tokenFor(repository.host);
    if (!mounted) return;
    setState(() {
      _savedTokenHost = saved == null ? null : repository.host;
      if (saved != null) _access = _Access.token;
    });
  }

  CredentialKind get _credential => _isSsh
      ? CredentialKind.sshKey
      : _access == _Access.token
      ? CredentialKind.token
      : CredentialKind.none;

  Future<void> _check() async {
    final manager = _manager;
    if (manager == null) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final repository = parseRemote(_url.text);
      if (repository != null &&
          _credential == CredentialKind.token &&
          _token.text.trim().isNotEmpty) {
        await manager.saveToken(
          repository.host,
          RepositoriesManager.tokenUser(repository.host),
          _token.text.trim(),
        );
        _token.clear();
        _savedTokenHost = repository.host;
      }
      final plan = await manager.prepare(_url.text, credential: _credential);
      setState(() {
        _plan = plan;
        _branch = plan.defaultBranch ?? plan.branches.first;
      });
    } on HostKeyUnknown catch (unknown) {
      if (await _askToTrust(unknown) == true) {
        await manager.trustHostKey(unknown.fingerprint);
        setState(() => _busy = false);
        return _check();
      }
    } on AuthFailed catch (error) {
      setState(
        () => _problem = _isSsh
            ? 'The server refused this phone\'s SSH key. Add the public key below to your account, then try again.\n(${error.message})'
            : 'The server wants a token with access to this repository.\n(${error.message})',
      );
    } on FormatException catch (error) {
      setState(() => _problem = error.message);
    } on RemoteFailure catch (error) {
      setState(() => _problem = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn(Forge forge) async {
    final account = await showModalBottomSheet<ForgeAccount>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SignInSheet(flow: _flow, forge: forge),
    );
    final manager = _manager;
    if (account == null || manager == null || !mounted) return;
    await manager.saveToken(
      account.host,
      RepositoriesManager.tokenUser(account.host),
      account.token,
    );
    setState(() {
      _account = account;
      _access = _Access.token;
      _savedTokenHost = account.host;
      if (_name.text.trim().isEmpty) _name.text = account.name;
      if (_email.text.trim().isEmpty && account.email != null) {
        _email.text = account.email!;
      }
    });
    try {
      final repositories = await _flow.repositories(account);
      if (mounted) setState(() => _repositories = repositories);
    } on SignInFailed catch (error) {
      if (mounted) setState(() => _problem = error.message);
    }
  }

  Future<bool?> _askToTrust(HostKeyUnknown unknown) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Trust ${unknown.host}?'),
      content: SelectableText(
        'This phone has not connected to ${unknown.host} before. Its key\'s fingerprint is\n\n'
        '${unknown.fingerprint}\n\n'
        'Compare it with the one your host publishes (for GitHub: docs.github.com, "GitHub\'s SSH key fingerprints"). '
        'If they differ, someone may be in between.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Trust'),
        ),
      ],
    ),
  );

  Future<void> _clone() async {
    final manager = _manager;
    final plan = _plan;
    if (manager == null || plan == null) return;
    setState(() {
      _busy = true;
      _problem = null;
      _progress = null;
    });
    try {
      final identity = _name.text.trim().isEmpty && _email.text.trim().isEmpty
          ? null
          : (name: _name.text.trim(), email: _email.text.trim());
      final record = await manager.add(
        plan,
        branch: _branch,
        depth: _fullHistory ? null : defaultDepth,
        identity: identity,
        onStart: (operation) => _operation = operation,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) Navigator.of(context).pop(record);
    } on Cancelled {
      if (mounted) setState(() => _problem = 'Cancelled; nothing was kept.');
    } on RemoteFailure catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } finally {
      _operation = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final repository = parseRemote(_url.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Add a repository')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_account == null &&
                (_flow.offers(Forge.github) || _flow.offers(Forge.gitlab))) ...[
              Wrap(
                spacing: 8,
                children: [
                  if (_flow.offers(Forge.github))
                    OutlinedButton(
                      onPressed: _busy ? null : () => _signIn(Forge.github),
                      child: const Text('Sign in with GitHub'),
                    ),
                  if (_flow.offers(Forge.gitlab))
                    OutlinedButton(
                      onPressed: _busy ? null : () => _signIn(Forge.gitlab),
                      child: const Text('Sign in with GitLab'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Or enter an address:'),
            ],
            if (_account != null)
              Text('Signed in to ${_account!.host} as ${_account!.login}.'),
            if (_repositories != null && _plan == null) ...[
              const SizedBox(height: 8),
              for (final repository in _repositories!.take(30))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    repository.private ? Icons.lock_outline : Icons.public,
                    size: 20,
                  ),
                  title: Text(repository.fullName),
                  onTap: _busy
                      ? null
                      : () {
                          _url.text = repository.cloneUrl;
                          _check();
                        },
                ),
              const Divider(),
            ],
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: 'https://github.com/owner/repo or git@github.com:owner/repo.git',
              ),
            ),
            const SizedBox(height: 16),
            if (repository != null && _isSsh) ...[
              Text(
                'Over SSH, with this phone\'s key',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'The server must know this public key (on GitHub: Settings → SSH and GPG keys).',
              ),
              if (_publicKey != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  _publicKey!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _publicKey!)),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy public key'),
                ),
              ],
            ] else if (repository != null) ...[
              SegmentedButton<_Access>(
                segments: const [
                  ButtonSegment(value: _Access.public, label: Text('Public')),
                  ButtonSegment(
                    value: _Access.token,
                    label: Text('With a token'),
                  ),
                ],
                selected: {_access},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _access = value.single;
                        _plan = null;
                      }),
              ),
              if (_access == _Access.token) ...[
                const SizedBox(height: 8),
                if (_savedTokenHost == repository.host)
                  Text(
                    'Using the token kept for ${repository.host}. Enter another to replace it.',
                  ),
                TextField(
                  controller: _token,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Token for ${repository.host}',
                    helperText:
                        'Kept in this phone\'s keychain, sent only to ${repository.host}.',
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            if (plan == null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _busy || repository == null ? null : _check,
                  child: Text(_busy ? 'Checking…' : 'Continue'),
                ),
              ),
            if (plan != null) ...[
              Text(
                '${plan.repository.host}/${plan.repository.path}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _branch,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  for (final branch in plan.branches)
                    DropdownMenuItem(value: branch, child: Text(branch)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _branch = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Full history'),
                subtitle: Text(
                  _fullHistory
                      ? 'Every commit: larger and slower.'
                      : 'The newest $defaultDepth commits; older ones are fetched when needed.',
                ),
                value: _fullHistory,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _fullHistory = value),
              ),
              if (plan.hasContentBranch && _branch != 'genbeya')
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Its content branch (genbeya) comes along: tasks and pages edited on it reach everyone.',
                  ),
                ),
              TextField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name in commits',
                ),
              ),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Your email in commits',
                ),
              ),
              const SizedBox(height: 16),
              if (_busy && _progress != null) ...[
                LinearProgressIndicator(
                  value: _progress!.totalObjects == 0
                      ? null
                      : (_progress!.receivedObjects +
                                _progress!.indexedDeltas) /
                            (_progress!.totalObjects + _progress!.totalDeltas),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_progress!.receivedObjects} of ${_progress!.totalObjects} objects, ${formatBytes(_progress!.receivedBytes)}',
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _clone,
                    child: Text(_busy ? 'Cloning…' : 'Clone'),
                  ),
                  const SizedBox(width: 8),
                  if (_busy && _operation != null)
                    TextButton(
                      onPressed: () => _manager?.cancel(_operation!),
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 16),
              Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
