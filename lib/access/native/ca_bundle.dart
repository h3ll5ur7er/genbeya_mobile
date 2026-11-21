/// Trusted CA certificates for the Git core's OpenSSL on Android.
///
/// OpenSSL finds certificates in a folder by the hash in their file names.
/// Android names them by OpenSSL's old hash (`subject_hash_old`), which current
/// OpenSSL doesn't look up, and since Android 14 the live store is the
/// Conscrypt module's. So the app reads the system's certificates once at
/// start and writes them as one PEM file, which OpenSSL loads whole.
library;

import 'dart:io';

/// The system's certificate folders, newest first.
const androidCaFolders = [
  '/apex/com.android.conscrypt/cacerts',
  '/system/etc/security/cacerts',
];

final _certificate = RegExp(
  r'-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----',
);

/// Writes the certificates of the first folder that has any to `bundle` and
/// returns how many there were; 0 when none was found.
Future<int> writeCaBundle(
  File bundle, {
  List<String> folders = androidCaFolders,
}) async {
  for (final path in folders) {
    final folder = Directory(path);
    if (!await folder.exists()) continue;
    final pems = <String>[];
    await for (final entry in folder.list()) {
      if (entry is! File) continue;
      try {
        pems.addAll(
          _certificate.allMatches(await entry.readAsString()).map((m) => m[0]!),
        );
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    if (pems.isEmpty) continue;
    await bundle.parent.create(recursive: true);
    await bundle.writeAsString('${pems.join('\n')}\n', flush: true);
    return pems.length;
  }
  return 0;
}
