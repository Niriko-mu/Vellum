import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/diagnostic_log.dart';

/// A stack trace on its own is not actionable. The report has to say which
/// build it came from — R8 names only line up with that version's mapping file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await DiagnosticLog.clear();
  });

  test('the report names the build before the entries', () async {
    await DiagnosticLog.init();
    await DiagnosticLog.record(Exception('boom'), null, context: 'unit');

    final report = await DiagnosticLog.composeReport();

    expect(report, startsWith('Vellum 诊断日志'));
    expect(report, contains('导出时间：'));
    expect(report, contains('未上传任何内容'));
    expect(report, contains('os: '));
    expect(report, contains('dart: '));
    expect(report, contains('--- 记录 ---'));

    // The header comes first, the actual error after it.
    final headerAt = report.indexOf('导出时间：');
    final entryAt = report.indexOf('Exception: boom');
    expect(headerAt, lessThan(entryAt));
  });

  test('an empty log still produces a usable report', () async {
    await DiagnosticLog.clear();
    final report = await DiagnosticLog.composeReport();
    expect(report, contains('Vellum 诊断日志'));
    expect(report, contains('--- 记录 ---'));
  });
}
