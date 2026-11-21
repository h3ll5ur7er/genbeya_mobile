import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/native/ca_bundle.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('ca'));
  tearDown(() => temp.deleteSync(recursive: true));

  String pem(String body) =>
      '-----BEGIN CERTIFICATE-----\n$body\n-----END CERTIFICATE-----';

  test(
    'writes the PEM blocks it is given, without the text around them',
    () async {
      final bundle = File('${temp.path}/out/system-ca.pem');
      final count = await writePemBundle(bundle, [
        'Certificate:\n  Data: ...\n${pem('AAA')}',
        pem('BBB'),
      ]);
      expect(count, 2);
      expect(bundle.readAsStringSync(), '${pem('AAA')}\n${pem('BBB')}\n');
    },
  );

  test(
    'falls back to the first folder that has certificates, skipping the others',
    () async {
      final empty = Directory('${temp.path}/apex')..createSync();
      final system = Directory('${temp.path}/system')..createSync();
      File('${system.path}/5ed36f99.0')
          .writeAsStringSync('Certificate:\n${pem('AAA')}\n');
      File('${system.path}/notes.txt').writeAsStringSync('no certificate here');
      final bundle = File('${temp.path}/system-ca.pem');

      final (count, from) = await writeCaBundleFromFolders(
        bundle,
        folders: [
          empty.path,
          '${temp.path}/missing',
          '${system.path}/5ed36f99.0',
          system.path,
        ],
      );

      expect((count, from), (1, system.path));
      expect(bundle.readAsStringSync(), contains(pem('AAA')));
    },
  );

  test('writes nothing and never throws when nothing is found', () async {
    final bundle = File('${temp.path}/system-ca.pem');
    expect(
      await writeCaBundleFromFolders(bundle, folders: ['${temp.path}/missing']),
      (0, null),
    );
    expect(await writePemBundle(bundle, ['nothing']), 0);
    expect(bundle.existsSync(), isFalse);
  });
}
