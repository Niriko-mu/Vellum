import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/vellum_update_service.dart';

/// A failed update check must not dump a ClientException with the full URL on
/// the reader. What they need is the one thing they can act on.
void main() {
  test('a host lookup failure names the network, not the exception', () {
    // The exact shape the reader saw on a device with no network:
    // "ClientException with SocketException: Failed host lookup:
    //  'api.github.com' (OS Error: No address associated with hostname, errno = 7)"
    final hint = updateNetworkHint(
      'ClientException with SocketException: Failed host lookup: '
      "'api.github.com' (OS Error: No address associated with hostname, "
      'errno = 7), uri=https://api.github.com/repos/x/y/releases/latest',
    );

    expect(hint, isNotNull);
    expect(hint, contains('网络'));
    expect(hint, isNot(contains('SocketException')));
    expect(hint, isNot(contains('errno')));
  });

  test('a timeout says so plainly', () {
    expect(
      updateNetworkHint('TimeoutException after 0:00:15.000000'),
      contains('超时'),
    );
  });

  test('a TLS failure is not reported as "no network"', () {
    expect(
      updateNetworkHint('HandshakeException: CERTIFICATE_VERIFY_FAILED'),
      contains('安全连接'),
    );
  });

  test('an unrecognised failure makes no claim about the network', () {
    expect(updateNetworkHint('WeirdError: something else entirely'), isNull);
  });
}
