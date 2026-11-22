import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/diagnostic_log.dart';

/// The log runs from the global error handlers, where a second failure would
/// lose the first one. Everything here is about it never throwing and never
/// growing without bound.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await DiagnosticLog.clear();
  });

  test('an error is kept even before storage is available', () async {
    // No platform channel in a unit test: `init` cannot open the file, so the
    // entry must still be held in memory rather than dropped.
    await DiagnosticLog.init();
    await DiagnosticLog.record(
      StateError('boom'),
      StackTrace.current,
      context: 'test',
    );

    final text = await DiagnosticLog.read();
    expect(text, contains('StateError'));
    expect(text, contains('boom'));
    expect(text, contains('at: test'));
    expect(text, contains('--- '), reason: 'entries are timestamped');
  });

  test('recording does not throw when the message is huge', () async {
    await DiagnosticLog.init();
    final huge = 'x' * (300 * 1024);
    // Must complete, not throw: a dropped log entry is fine, a crash in the
    // crash handler is not.
    await DiagnosticLog.record(Exception(huge), null, context: 'huge');
    expect(await DiagnosticLog.read(), isNotEmpty);
  });

  test('a failure with no stack trace is still recorded', () async {
    await DiagnosticLog.init();
    await DiagnosticLog.record(ArgumentError('no stack'), null);
    expect(await DiagnosticLog.read(), contains('ArgumentError'));
  });

  test('clearing empties the log', () async {
    await DiagnosticLog.init();
    await DiagnosticLog.record(Exception('gone'), null);
    await DiagnosticLog.clear();
    expect((await DiagnosticLog.read()).trim(), isEmpty);
  });

  test('the environment snapshot reports the platform, not the reader', () {
    final env = DiagnosticLog.environment();
    expect(env['os'], isNotEmpty);
    expect(env.keys, containsAll(['dart', 'os', 'debug']));
  });

  test('the cap is small enough for a phone', () {
    // 200 KB: a reader reporting a bug should be able to mail this.
    expect(DiagnosticLog.maxBytes, lessThanOrEqualTo(512 * 1024));
  });
}
