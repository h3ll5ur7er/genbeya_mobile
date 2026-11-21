/// Trusted CA certificates for the Git core's OpenSSL on Android.
///
/// The vendored OpenSSL knows no store on Android and is built without file
/// access (`no-stdio`), so it can't read a CA file or folder. The app asks
/// Android for the system's trusted certificates (`AndroidCAStore`, through
/// MainActivity.kt) and hands them to the core in memory, DER-encoded
/// (`add_ca_certificates`). The certificate folders are a fallback source.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The system's certificate folders, newest first.
const androidCaFolders = [
  '/apex/com.android.conscrypt/cacerts',
  '/system/etc/security/cacerts',
];

final _certificate = RegExp(
  r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
);

/// What the app trusts, for the Git core's screen.
class CaBundleStatus {
  CaBundleStatus._();

  /// "146 certificates from Android", or what went wrong.
  static String description = 'not set up yet';
}

/// The DER bytes of every PEM certificate in `pems`; text around them and
/// blocks that aren't Base64 are skipped.
List<Uint8List> derCertificates(Iterable<String> pems) => [
  for (final pem in pems)
    for (final match in _certificate.allMatches(pem)) ?_decode(match[1]!),
];

Uint8List? _decode(String body) {
  try {
    final der = base64Decode(body.replaceAll(RegExp(r'\s'), ''));
    return der.isEmpty ? null : der;
  } on FormatException {
    return null;
  }
}

/// The PEM text of the files in the first readable folder that has any
/// certificate, and where; empty when none. Never throws: a folder the app may
/// not list is skipped.
Future<(List<String>, String?)> pemsFromFolders({
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
      if (derCertificates(pems).isNotEmpty) return (pems, path);
    } on Object {
      continue;
    }
  }
  return (const <String>[], null);
}
