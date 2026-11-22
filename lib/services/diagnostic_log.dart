import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A rolling, on-device record of what went wrong.
///
/// The release build has no crash reporting: R8 renames every class, so a stack
/// trace the reader sends back is unreadable without the mapping file, and there
/// was nothing on the device keeping one at all. The honest minimum is to keep
/// the last few errors locally and let the reader hand them over — that is what
/// this does. It never sends anything anywhere.
///
/// Deliberately incapable of throwing or blocking: it runs from the global error
/// handlers, where a second failure would lose the first one.
abstract final class DiagnosticLog {
  /// Kept deliberately small: this is a phone's private storage, and the log is
  /// only ever read by the reader pressing 导出诊断日志.
  static const int maxBytes = 200 * 1024;

  /// Errors captured before the app directory is available.
  static final List<String> _pending = [];

  static File? _file;
  static bool _ready = false;

  /// Prepares the log file. Safe to call more than once.
  static Future<void> init() async {
    if (_ready) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}${Platform.pathSeparator}logs');
      if (!await logDir.exists()) await logDir.create(recursive: true);
      _file = File('${logDir.path}${Platform.pathSeparator}vellum.log');
      _ready = true;
      if (_pending.isNotEmpty) {
        final buffered = List<String>.from(_pending);
        _pending.clear();
        for (final line in buffered) {
          await _append(line);
        }
      }
    } catch (_) {
      // No storage: the log simply stays in memory for this session.
    }
  }

  /// Records one error. [context] says where it happened in reader terms.
  static Future<void> record(
    Object error,
    StackTrace? stack, {
    String? context,
  }) async {
    final entry = StringBuffer()
      ..writeln('--- ${DateTime.now().toIso8601String()}')
      ..writeln(context == null ? '' : 'at: $context')
      ..writeln('${error.runtimeType}: $error');
    if (stack != null) entry.writeln(stack.toString().trimRight());
    final text = entry.toString();

    // Also goes to logcat in debug so a developer sees it immediately. Bounded:
    // one enormous message must not turn into a megabyte of console output.
    final preview = text.length > 2000 ? '${text.substring(0, 2000)}…' : text;
    debugPrint('Vellum diagnostic: $preview');

    if (!_ready) {
      // Buffered, bounded: a startup crash loop must not grow without limit.
      _pending.add(text);
      if (_pending.length > 20) _pending.removeAt(0);
      return;
    }
    await _append(text);
  }

  static Future<void> _append(String text) async {
    final file = _file;
    if (file == null) return;
    try {
      final exists = await file.exists();
      if (exists && await file.length() > maxBytes) {
        await _rotate(file);
      }
      await file.writeAsString(
        text,
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never become a failure path of its own.
    }
  }

  /// Keeps the newest half, so the file cannot grow past its cap and the most
  /// recent crash — the one the reader is reporting — survives.
  static Future<void> _rotate(File file) async {
    try {
      final text = await file.readAsString();
      final keepFrom = text.length - (maxBytes ~/ 2);
      var cut = keepFrom < 0 ? 0 : keepFrom;
      if (cut > 0) {
        final next = text.indexOf('--- ', cut);
        if (next >= 0) cut = next;
      }
      await file.writeAsString(text.substring(cut), flush: true);
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// The log with a header identifying the build it came from.
  ///
  /// A stack trace on its own is not actionable: the same code path can fail on
  /// one Android version and not another, and R8's names only line up with the
  /// mapping file of *that* version. The header is what makes an exported file
  /// answerable weeks later.
  static Future<String> composeReport() async {
    final buffer = StringBuffer()
      ..writeln('Vellum 诊断日志')
      ..writeln('导出时间：${DateTime.now().toLocal()}')
      ..writeln('未上传任何内容，仅本机记录。');
    for (final entry in environment().entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer
      ..writeln()
      ..writeln('--- 记录 ---');
    buffer.write(await read());
    return buffer.toString();
  }

  /// Copies the log somewhere the reader can share it from.
  ///
  /// Written with a timestamped name so repeated exports do not overwrite each
  /// other, and flushed so the file is complete when the share sheet opens.
  static Future<File?> export(String targetDirectory) async {
    final file = _file;
    if (file == null || !await file.exists()) return null;
    try {
      final dir = Directory(targetDirectory);
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .split('+')
          .first;
      final target = File(
        '${dir.path}${Platform.pathSeparator}vellum-$stamp.log',
      );
      await target.writeAsString(await composeReport(), flush: true);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// Everything currently in the log, or empty when there is none.
  static Future<String> read() async {
    final file = _file;
    if (file == null) return _pending.join();
    try {
      if (!await file.exists()) return _pending.join();
      return await file.readAsString();
    } catch (_) {
      return _pending.join();
    }
  }

  /// Wipes the log (settings 清除诊断日志).
  static Future<void> clear() async {
    _pending.clear();
    try {
      final file = _file;
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// One-line description of the build, for the top of an exported log.
  static Map<String, Object?> environment() => {
    'dart': Platform.version,
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'locale': jsonEncode(Platform.localeName),
    'debug': kDebugMode,
  };
}
