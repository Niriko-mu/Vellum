import 'dart:async';
import 'dart:io';

/// Serializes callers in the shared Flutter engine and holds an OS advisory
/// lock for cooperating processes. Nested library operations reuse the lease.
class LibraryFileMutex {
  static final _zoneKey = Object();
  static Future<void> _tail = Future<void>.value();
  static Future<T> run<T>(String path, Future<T> Function() operation) async {
    if (Zone.current[_zoneKey] == path) return operation();
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    RandomAccessFile? lock;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      lock = await file.open(mode: FileMode.append);
      await lock.lock(FileLock.blockingExclusive);
      return await runZoned(operation, zoneValues: {_zoneKey: path});
    } finally {
      try {
        if (lock != null) await lock.close();
      } finally {
        done.complete();
      }
    }
  }
}
