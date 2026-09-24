// E2E clocking: the staff app never asked iOS for "Always" location —
// geolocator returns "While Using" as it stands — so every real iPhone
// clock-in was marked "tracking off" and the manager told. The upgrade is
// asked once, through the host; "Always" already, or asked before, asks
// nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:madar_staff/always_location.dart';

void main() {
  late LocationPermission status;
  late int asks;
  late bool askedBefore;
  bool? answer;

  AlwaysLocation make() => AlwaysLocation(
    check: () async => status,
    request: () async => status = LocationPermission.whileInUse,
    askAlways: () async {
      asks += 1;
      if (answer == true) status = LocationPermission.always;
      return answer;
    },
    asked: () => askedBefore,
    markAsked: () async => askedBefore = true,
  );

  setUp(() {
    status = LocationPermission.whileInUse;
    asks = 0;
    askedBefore = false;
    answer = null;
  });

  test('While Using: asks for Always once, and takes the answer', () async {
    answer = true;
    expect(await make()(), isTrue);
    expect(asks, 1);
    expect(askedBefore, isTrue);
  });

  test('Kept While Using: tracking off, and never asked again', () async {
    answer = false;
    expect(await make()(), isFalse);
    expect(await make()(), isFalse);
    expect(
      asks,
      1,
      reason: 'iOS shows the upgrade once; asking again would only wait',
    );
  });

  test('No answer in time: reads the permission as it stands', () async {
    expect(await make()(), isFalse);
    expect(asks, 1);
  });

  test('Not asked yet: While Using first, then Always', () async {
    status = LocationPermission.denied;
    answer = true;
    expect(await make()(), isTrue);
    expect(asks, 1);
  });

  test('Always already, or refused outright: nothing is asked', () async {
    status = LocationPermission.always;
    expect(await make()(), isTrue);
    status = LocationPermission.deniedForever;
    expect(await make()(), isFalse);
    expect(asks, 0);
  });
}
