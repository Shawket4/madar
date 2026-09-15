import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/lan_bonjour.dart';

void main() {
  test('pickHost prefers IPv4, skips loopback and link-local IPv6', () {
    expect(LanBonjour.pickHost(['fe80::1', '192.168.1.20']), '192.168.1.20');
    expect(LanBonjour.pickHost(['127.0.0.1', 'fe80::1']), isNull);
    expect(LanBonjour.pickHost(['2001:db8::5', 'bogus']), '2001:db8::5');
    expect(LanBonjour.pickHost([]), isNull);
  });
}
