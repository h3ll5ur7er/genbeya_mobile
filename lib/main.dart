import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'access/native/ca_bundle.dart';
import 'app.dart';
import 'src/rust/api/git.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: GenbeyaApp()));
  // After the app is up: nothing here may keep it from starting.
  if (Platform.isAndroid) unawaited(_trustAndroidCertificates());
}

const _certificates = MethodChannel('fyi.genbeya/certificates');

/// Hands the Git core the system's trusted certificates, in memory: from
/// Android's store, else from its certificate folders.
Future<void> _trustAndroidCertificates() async {
  try {
    var source = 'Android';
    var pems = <String>[];
    try {
      pems =
          await _certificates.invokeListMethod<String>('systemCertificates') ??
          const [];
    } on Object catch (error) {
      CaBundleStatus.description = 'Android store unavailable ($error)';
    }
    if (derCertificates(pems).isEmpty) {
      final (folderPems, folder) = await pemsFromFolders();
      pems = folderPems;
      source = folder ?? '';
    }
    final certificates = derCertificates(pems);
    if (certificates.isEmpty) {
      CaBundleStatus.description = 'no certificates found: HTTPS will fail';
      return;
    }
    final added = await addCaCertificates(certificates: certificates);
    CaBundleStatus.description =
        '$added of ${certificates.length} certificates from $source';
  } on Object catch (error) {
    CaBundleStatus.description = 'setting up certificates failed: $error';
  }
}
