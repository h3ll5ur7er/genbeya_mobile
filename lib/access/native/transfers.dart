/// Clones and fetches stream their progress and end with how they went
/// (`TransferEvent` in native/genbeya_core/src/api/git.rs).
library;

import '../../src/rust/api/git.dart';
import '../../src/rust/git.dart';

/// Runs a clone or fetch to its end, passing progress to [onProgress]; throws
/// the [CoreError] it failed with.
Future<void> runTransfer(
  Stream<TransferEvent> events, {
  void Function(Progress progress)? onProgress,
}) async {
  var done = false;
  await for (final event in events) {
    switch (event) {
      case TransferEvent_Progress(:final field0):
        onProgress?.call(field0);
      case TransferEvent_Done():
        done = true;
      case TransferEvent_Failed(:final field0):
        throw field0;
    }
  }
  if (!done) throw StateError('The transfer ended without saying how it went.');
}
