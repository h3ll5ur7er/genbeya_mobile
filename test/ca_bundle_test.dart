import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/native/ca_bundle.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('ca'));
  tearDown(() => temp.deleteSync(recursive: true));

  String pem(List<int> der) =>
      '-----BEGIN CERTIFICATE-----\n${base64Encode(der)}\n-----END CERTIFICATE-----';

  test('decodes the PEM blocks it is given, without the text around them', () {
    final ders = derCertificates([
      'Certificate:\n  Data: ...\n${pem([1, 2, 3])}',
      pem([4, 5]),
      '-----BEGIN CERTIFICATE-----\n!!not base64!!\n-----END CERTIFICATE-----',
      'no certificate here',
    ]);
    expect(ders, [
      [1, 2, 3],
      [4, 5],
    ]);
  });

  test(
    'falls back to the first folder that has certificates, skipping the others',
    () async {
      final empty = Directory('${temp.path}/apex')..createSync();
      final system = Directory('${temp.path}/system')..createSync();
      File('${system.path}/5ed36f99.0')
          .writeAsStringSync('Certificate:\n${pem([9, 9])}\n');
      File('${system.path}/notes.txt').writeAsStringSync('no certificate here');

      final (pems, from) = await pemsFromFolders(
        folders: [
          empty.path,
          '${temp.path}/missing',
          '${system.path}/5ed36f99.0',
          system.path,
        ],
      );

      expect(from, system.path);
      expect(derCertificates(pems), [
        [9, 9],
      ]);
    },
  );

  test(
    'finds nothing and never throws when no folder has certificates',
    () async {
      final (pems, from) = await pemsFromFolders(
        folders: ['${temp.path}/missing'],
      );
      expect(pems, isEmpty);
      expect(from, isNull);
    },
  );
}
