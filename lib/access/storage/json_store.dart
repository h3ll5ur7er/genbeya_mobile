import 'dart:convert';
import 'dart:io';

/// One JSON document in the app's storage, written atomically: a crash
/// mid-write leaves the previous version.
class JsonStore {
  JsonStore(this.file);

  final File file;

  /// The document, or null when there is none yet or it can't be read.
  Future<Object?> read() async {
    try {
      return jsonDecode(await file.readAsString());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(Object? value) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
