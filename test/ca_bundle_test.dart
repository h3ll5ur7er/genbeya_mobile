import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/native/ca_bundle.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('ca'));
  tearDown(() => temp.deleteSync(recursive: true));

  String pem(String body) =>
      '-----BEGIN CERTIFICATE-----\n$body\n-----END CERTIFICATE-----';

  test('collects the PEM blocks of the first folder that has any, skipping the text around them', () async {
    final empty = Directory('${temp.path}/apex')..createSync();
    final system = Directory('${temp.path}/system')..createSync();
    // Android's files carry `openssl x509 -text` output before the PEM block.
    File('${system.path}/5ed36f99.0')
        .writeAsStringSync('Certificate:\n  Data: ...\n${pem('AAA')}\n');
    File('${system.path}/a94d09e5.0').writeAsStringSync(pem('BBB'));
    File('${system.path}/notes.txt').writeAsStringSync('no certificate here');
    final bundle = File('${temp.path}/out/system-ca.pem');

    final count = await writeCaBundle(
      bundle,
      folders: [empty.path, '${temp.path}/missing', system.path],
    );

    expect(count, 2);
    final text = bundle.readAsStringSync();
    expect(text, contains(pem('AAA')));
    expect(text, contains(pem('BBB')));
    expect(text, isNot(contains('Certificate:')));
  });

  test('writes nothing when no folder has certificates', () async {
    final bundle = File('${temp.path}/system-ca.pem');
    expect(await writeCaBundle(bundle, folders: ['${temp.path}/missing']), 0);
    expect(bundle.existsSync(), isFalse);
  });
}
