/// Trusted CA certificates for the Git core's OpenSSL on Android.
///
/// The vendored OpenSSL knows no store on Android. The app asks Android for
/// the system's trusted certificates (`AndroidCAStore`, through
/// MainActivity.kt) and writes them as one PEM file, which OpenSSL loads
/// whole. The certificate folders are the fallback: OpenSSL can't use them
/// directly, since Android names the files by OpenSSL's old hash, and since
/// Android 14 the live store is the Conscrypt module's.
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

/// What the app trusts, for the Git core's screen.
class CaBundleStatus {
  CaBundleStatus._();

  /// "146 certificates from Android", or what went wrong.
  static String description = 'not set up yet';
}

/// Writes `pems` to `bundle`; returns how many there were.
Future<int> writePemBundle(File bundle, Iterable<String> pems) async {
  final certificates = [
    for (final pem in pems) ..._certificate.allMatches(pem).map((m) => m[0]!),
  ];
  if (certificates.isEmpty) return 0;
  await bundle.parent.create(recursive: true);
  await bundle.writeAsString('${certificates.join('\n')}\n', flush: true);
  return certificates.length;
}

/// Writes the certificates of the first readable folder that has any to
/// `bundle`; returns how many and from where, or 0. Never throws: a folder the
/// app may not list is skipped.
Future<(int, String?)> writeCaBundleFromFolders(
  File bundle, {
  List<String> folders = androidCaFolders,
}) async {
  for (final path in folders) {
    try {
      final folder = Directory(path);
      if (!await folder.exists()) continue;
      final pems = <String>[];
      await for (final entry in folder.list()) {
        if (entry is! File) continue;
        try {
          pems.add(await entry.readAsString());
        } on Object {
          continue;
        }
      }
      final count = await writePemBundle(bundle, pems);
      if (count > 0) return (count, path);
    } on Object {
      continue;
    }
  }
  return (0, null);
}
