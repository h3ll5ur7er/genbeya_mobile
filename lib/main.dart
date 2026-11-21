import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'src/rust/api/git.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // The vendored OpenSSL knows no CA store on Android; iOS uses the system's.
  if (Platform.isAndroid) {
    await setCaLocations(dir: '/system/etc/security/cacerts');
  }
  runApp(const ProviderScope(child: GenbeyaApp()));
}
