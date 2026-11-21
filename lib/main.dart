import 'dart:io';

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
  // The vendored OpenSSL knows no CA store on Android (iOS uses the system's):
  // hand it the system's certificates as one file.
  if (Platform.isAndroid) {
    final bundle = File(
      '${(await getApplicationSupportDirectory()).path}/system-ca.pem',
    );
    if (await writeCaBundle(bundle) > 0) {
      await setCaLocations(file: bundle.path);
    }
  }
  runApp(const ProviderScope(child: GenbeyaApp()));
}
