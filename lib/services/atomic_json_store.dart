import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One JSON document on disk, written so that a crash cannot truncate it.
///
/// Every library here does read-modify-write on a single file: the whole note
/// list, the whole draft list, the whole reading-progress map. Writing straight
/// onto the live file meant an interrupted write (process kill, full disk,
/// power loss) left a half-written JSON behind — and because every reader
/// swallowed parse errors into "empty", the next save then persisted that empty
/// document over the good one. The notes the reader wrote were gone and nothing
/// had reported a problem.
///
/// The fix has two halves, and both are required:
///
/// * [write] goes to `<file>.next`, flushes, then renames over the target —
///   rename is atomic within a directory, so a reader either sees the old
///   document or the new one, never half of either.
/// * [read] distinguishes "no file yet" from "the file is unreadable". The
///   second case quarantines the file and reports failure, so a caller that
///   modifies-and-saves never overwrites data it failed to understand.
///
/// Not using [LibraryFileMutex] here on purpose: these documents are small and
/// the mutex's advisory lock costs an extra file handle per save. Serialisation
/// is the caller's job ([AtomicJsonStore.serialised]).
abstract final class AtomicJsonStore {
  /// Suffix of the staged file. Kept next to the target so [File.rename] stays
  /// within one directory (a cross-device rename is a copy, not an atomic move).
  static const stagingSuffix = '.next';

  /// Suffix of a quarantined document. Never deleted automatically: it is the
  /// only copy left of whatever the reader had before the file went bad.
  static const quarantineSuffix = '.corrupt';

  /// Writes [text] to [target] atomically.
  ///
  /// Leaves the previous document untouched on failure and rethrows, so a
  /// caller can surface "save failed" instead of pretending it succeeded.
  static Future<void> write(File target, String text) async {
    final parent = target.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    final staging = File('${target.path}$stagingSuffix');
    try {
      await staging.writeAsString(text, flush: true);
      await staging.rename(target.path);
    } catch (_) {
      // A failed rename leaves the staged copy behind; remove it so the next
      // save starts clean instead of appending to a stale buffer.
      try {
        if (await staging.exists()) await staging.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Reads [file], or reports what happened instead of guessing.
  ///
  /// [missing] is the answer for a file that has never been written: callers
  /// treat that as "first run" and are free to create it. [damaged] means the
  /// bytes are there but cannot be understood — the file is renamed aside and
  /// the caller must **not** rewrite the collection from an empty default.
  static Future<JsonReadResult> read(File file) async {
    if (!await file.exists()) return const JsonReadResult.missing();
    String text;
    try {
      text = await file.readAsString();
    } catch (error) {
      return JsonReadResult.damaged(error.toString(), quarantined: false);
    }
    if (text.trim().isEmpty) {
      // A zero-length document is what a killed non-atomic write used to leave.
      // Treat it as damaged rather than as an empty collection.
      return JsonReadResult.damaged(
        'empty document',
        quarantined: await _quarantine(file),
      );
    }
    // Validity is checked here rather than in every caller: a truncated write
    // is the exact failure this store exists for, and jsonDecode is the one
    // test that catches it for all of them.
    try {
      jsonDecode(text);
    } on FormatException catch (error) {
      return JsonReadResult.damaged(
        error.message,
        quarantined: await _quarantine(file),
      );
    }
    return JsonReadResult.text(text);
  }

  static Future<bool> _quarantine(File file) async {
    try {
      final target = File('${file.path}$quarantineSuffix');
      if (await target.exists()) await target.delete();
      await file.rename(target.path);
      return true;
    } catch (_) {
      // The file could not be moved aside (permissions, external storage gone).
      // Reporting damaged without quarantine still stops the caller from
      // overwriting it, which is the part that matters.
      return false;
    }
  }

  /// Runs [operation] after every earlier run on [key] has finished.
  ///
  /// The libraries are `const` and stateless, so two instances (the reader's
  /// notes controller and the settings page's importer, say) can enter
  /// read-modify-write on the same file at the same time and the later write
  /// wins with the earlier one's snapshot. This is the same tail-future chain
  /// [BookLibrary] uses, factored out.
  static Future<T> serialised<T>(String key, Future<T> Function() operation) async {
    final previous = _tails[key];
    final done = Completer<void>();
    _tails[key] = done.future;
    try {
      await previous;
    } catch (_) {
      // A previous caller's failure must not wedge the queue.
    }
    try {
      return await operation();
    } finally {
      done.complete();
      if (identical(_tails[key], done.future)) {
        _tails.remove(key);
      }
    }
  }

  static final Map<String, Future<void>> _tails = {};
}

/// What [AtomicJsonStore.read] found.
class JsonReadResult {
  const JsonReadResult.text(this.text)
    : missing = false,
      damaged = false,
      error = null,
      quarantined = false;

  const JsonReadResult.missing()
    : text = null,
      missing = true,
      damaged = false,
      error = null,
      quarantined = false;

  const JsonReadResult.damaged(this.error, {required this.quarantined})
    : text = null,
      missing = false,
      damaged = true;

  /// The document's contents, when it was readable.
  final String? text;

  /// No document exists yet — a first run, not a failure.
  final bool missing;

  /// The document exists but cannot be used. [error] says what went wrong.
  final bool damaged;

  /// Set when the damaged file was moved to `<path>.corrupt`.
  final bool quarantined;

  final String? error;
}
