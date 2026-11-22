import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/vellum_update_service.dart';

/// The updater must read the repository the release workflow actually
/// publishes to. It used to point at an older mirror whose newest release was
/// 1.0.15, so every reader on a GitHub build was told they were up to date.
void main() {
  test('the default repository is the one releases are published to', () {
    final ref = parseUpdateRepository(vellumDefaultRepository);
    expect(ref, isNotNull);
    expect(ref!.host, 'github.com');
    expect(ref.owner, 'niriko-mu');
    expect(ref.repo, 'Vellum');
    // The published API endpoint, not the web page.
    expect(
      ref.latestReleaseApi,
      'https://api.github.com/repos/niriko-mu/Vellum/releases/latest',
    );
  });

  test('a bare owner/repo resolves to the default host', () {
    final ref = parseUpdateRepository('niriko-mu/Vellum');
    expect(ref!.host, 'github.com');
    expect(ref.toString(), 'github.com/niriko-mu/Vellum');
  });

  test('spelling out a host still works, both ways', () {
    expect(
      parseUpdateRepository('github.com/a/b')!.toString(),
      'github.com/a/b',
    );
    expect(
      parseUpdateRepository('https://gitee.com/a/b')!.toString(),
      'gitee.com/a/b',
    );
    expect(
      parseUpdateRepository('www.github.com/a/b/')!.toString(),
      'github.com/a/b',
    );
  });

  test('a repository with too few parts is rejected', () {
    expect(parseUpdateRepository(''), isNull);
    expect(parseUpdateRepository('justoneword'), isNull);
    expect(parseUpdateRepository('https://'), isNull);
  });

  test('versions compare the way the updater decides "有新版本"', () {
    bool newer(String latest, String current) => VellumReleaseInfo(
      currentVersion: current,
      latestVersion: latest,
      notes: '',
      releaseUrl: '',
      assets: const {},
    ).hasUpdate;

    expect(newer('1.0.16', '1.0.15'), isTrue);
    expect(newer('1.1.0', '1.0.15'), isTrue, reason: '1.1.0 is newer than 1.0.15');
    expect(newer('1.0.15', '1.0.15'), isFalse);
    expect(newer('V1.0.15', '1.0.15'), isFalse, reason: 'the V prefix is stripped');
    expect(newer('1.1', '1.1.0'), isFalse, reason: 'missing parts count as zero');
    expect(newer('1.0.9', '1.0.10'), isFalse);
  });
}
