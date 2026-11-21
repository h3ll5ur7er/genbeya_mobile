import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

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

/// Hands the Git core's OpenSSL the system's trusted certificates as one file:
/// from Android's store, else from its certificate folders.
Future<void> _trustAndroidCertificates() async {
  try {
    final bundle = File(
      '${(await getApplicationSupportDirectory()).path}/system-ca.pem',
    );
    var (count, from) = (0, '');
    try {
      final pems =
          await _certificates.invokeListMethod<String>('systemCertificates') ??
          const [];
      count = await writePemBundle(bundle, pems);
      from = 'Android';
    } on Object catch (error) {
      CaBundleStatus.description = 'Android store unavailable ($error)';
    }
    if (count == 0) {
      final (folderCount, folder) = await writeCaBundleFromFolders(bundle);
      count = folderCount;
      from = folder ?? '';
    }
    if (count == 0) {
      CaBundleStatus.description = 'no certificates found: HTTPS will fail';
      return;
    }
    await setCaLocations(file: bundle.path);
    CaBundleStatus.description = '$count certificates from $from';
  } on Object catch (error) {
    CaBundleStatus.description = 'setting up certificates failed: $error';
  }
}
