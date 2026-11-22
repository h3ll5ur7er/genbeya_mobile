import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../access/forge/device_flow.dart';

/// Signing in with the device flow: the code to enter, the browser to enter
/// it in, and waiting until the forge says yes. Pops with the account.
class SignInSheet extends StatefulWidget {
  const SignInSheet({super.key, required this.flow, required this.forge});

  final DeviceFlow flow;
  final Forge forge;

  @override
  State<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<SignInSheet> {
  DeviceCode? _code;
  String? _problem;
  var _cancelled = false;

  String get _forgeName => switch (widget.forge) {
    Forge.github => 'GitHub',
    Forge.gitlab => 'GitLab',
  };

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final code = await widget.flow.start(widget.forge);
      if (!mounted) return;
      setState(() => _code = code);
      final account = await widget.flow.finish(
        widget.forge,
        code,
        cancelled: () => _cancelled,
      );
      if (mounted) Navigator.of(context).pop(account);
    } on SignInFailed catch (error) {
      if (mounted && !_cancelled) setState(() => _problem = error.message);
    } on Object catch (error) {
      if (mounted && !_cancelled) {
        setState(() => _problem = "Couldn't reach $_forgeName: $error");
      }
    }
  }

  Future<void> _open() async {
    final code = _code!;
    await Clipboard.setData(ClipboardData(text: code.userCode));
    await launchUrl(
      code.verificationUriComplete ?? code.verificationUri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign in with $_forgeName', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_problem != null)
              Text(_problem!, style: TextStyle(color: theme.colorScheme.error))
            else if (code == null)
              const LinearProgressIndicator()
            else ...[
              const Text('Enter this code on the page that opens:'),
              const SizedBox(height: 12),
              SelectableText(
                code.userCode,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_browser),
                label: Text(
                  'Copy the code and open ${code.verificationUri.host}',
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Waiting for you to confirm in the browser…'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
