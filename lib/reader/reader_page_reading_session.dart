import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/reading_stats.dart';

/// Tracks the current reading session and persists accumulated reading time.
///
/// It exposes notifiers for the view but owns no Flutter context or page state.
class ReaderReadingSession {
  ReaderReadingSession({
    required this.bookId,
    this.service = const ReadingStatsService(),
  });

  final String bookId;
  final ReadingStatsService service;
  final sessionSeconds = ValueNotifier<int>(0);
  final todaySeconds = ValueNotifier<int>(0);

  Stopwatch? _stopwatch;
  Timer? _timer;
  int _unflushedSeconds = 0;
  bool _disposed = false;

  /// Exact elapsed seconds; [sessionSeconds] only carries the value the pill
  /// renders.
  int _accumulatedSeconds = 0;

  /// The reading-time pill renders whole minutes, so a notification is only
  /// worth a frame when that minute changes.
  static int _displayBucket(int seconds) => (seconds ~/ 60) * 60;

  Future<void> loadToday() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final stats = await service.load().timeout(const Duration(seconds: 2));
      if (!_disposed) todaySeconds.value = stats.todaySeconds;
    } catch (_) {}
  }

  void start() {
    if (_disposed) return;
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    _stopwatch ??= Stopwatch()..start();
    if (!_stopwatch!.isRunning) _stopwatch!.start();
    // Accumulate every second, but only notify the view when the number it
    // actually renders changes. The reading-time pill shows minutes, so the
    // old per-second notification repainted the reader 3,600 times an hour to
    // change nothing on screen.
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final watch = _stopwatch;
      if (watch == null || !watch.isRunning) return;
      final elapsed = watch.elapsed.inSeconds;
      if (elapsed > _accumulatedSeconds) {
        _unflushedSeconds += elapsed - _accumulatedSeconds;
        _accumulatedSeconds = elapsed;
        final bucket = _displayBucket(elapsed);
        if (bucket != sessionSeconds.value) sessionSeconds.value = bucket;
      }
      if (_unflushedSeconds >= 10) flush();
    });
  }

  void pause() {
    _stopwatch?.stop();
    flush();
  }

  void flush() {
    final seconds = _unflushedSeconds;
    if (seconds <= 0) return;
    _unflushedSeconds = 0;
    service.addSeconds(bookId: bookId, seconds: seconds).then((stats) {
      // The final write is allowed to finish after leaving the reader, but
      // its notifier belongs to the page that has already been disposed.
      if (!_disposed) todaySeconds.value = stats.todaySeconds;
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _unflushedSeconds += 0;
    _stopwatch?.stop();
    flush();
    sessionSeconds.dispose();
    todaySeconds.dispose();
  }
}
