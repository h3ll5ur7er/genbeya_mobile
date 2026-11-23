import 'package:flutter/services.dart';

/// Text shared into the app from another app (Share → Genbeya Mobile): a
/// link from a chat, where `genbeya://` links aren't tappable. Android only
/// for now; iOS needs a share extension ([[GM-10]]).
class SharedText {
  static const _channel = MethodChannel('fyi.genbeya/shared');

  /// Calls [onShared] with text shared before the app was up, and with
  /// text shared while it runs.
  static Future<void> listen(void Function(String text) onShared) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) {
        onShared(call.arguments as String);
      }
    });
    try {
      final pending = await _channel.invokeMethod<String>('take');
      if (pending != null) onShared(pending);
    } on MissingPluginException {
      // Not on this platform.
    } on PlatformException {
      // Nothing to take.
    }
  }
}
