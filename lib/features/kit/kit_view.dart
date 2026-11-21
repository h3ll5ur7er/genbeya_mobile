import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../access/kit/kit_host.dart';
import '../../access/kit/kit_server.dart';

/// Genbeya's renderer and editor (the kit, `kit/dist/`) in a web view, served
/// from the loopback interface ([KitServer]) and talked to only through
/// messages, which [host] checks and answers; navigation never leaves the kit.
class KitView extends StatefulWidget {
  const KitView({super.key, required this.host, this.onRefused});

  final KitHost host;

  /// A navigation the view refused, for the log.
  final void Function(String reason)? onRefused;

  @override
  State<KitView> createState() => _KitViewState();
}

class _KitViewState extends State<KitView> {
  KitServer? _server;
  WebViewController? _controller;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _start();
  }

  static Future<Uint8List?> _loadAsset(String path) async {
    try {
      final data = await rootBundle.load('kit/dist/$path');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _start() async {
    if (await _loadAsset('kit.html') == null) {
      setState(
        () => _problem = "The kit isn't built. Run `node build.mjs` in tool/build_kit, then build the app again.",
      );
      return;
    }
    final server = await KitServer.start(_loadAsset);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'GenbeyaKit',
        onMessageReceived: (message) => widget.host.receive(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && server.owns(uri)) {
              return NavigationDecision.navigate;
            }
            widget.onRefused?.call('Navigation to ${request.url} refused.');
            return NavigationDecision.prevent;
          },
        ),
      );
    widget.host.attach(
      (message) => controller.runJavaScript(
        'window.genbeyaKit.receive(${jsonEncode(message)})',
      ),
    );
    await controller.loadRequest(server.kitUri);
    if (!mounted) {
      await server.close();
      return;
    }
    setState(() {
      _server = server;
      _controller = controller;
    });
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    if (problem != null) {
      return Padding(padding: const EdgeInsets.all(16), child: Text(problem));
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }
}
