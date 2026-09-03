/// Assertions are on the CAPTURED EVENT — what `_beforeSend` actually hands
/// back — not on the code that builds it. A tag set on the wrong scope still
/// produces an event; it just arrives empty, which looks like it works.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const redacted = '[redacted]';

/// Run an event through the real `beforeSend` hook the options install, rather
/// than calling a private copy of it. Going through [configureSentryOptions] is
/// what makes this test able to fail when the wiring is reverted.
SentryEvent? throughBeforeSend(SentryEvent event) {
  final options = SentryFlutterOptions()..dsn = 'https://public@example.invalid/2';
  configureSentryOptions(options);
  final hook = options.beforeSend;
  expect(hook, isNotNull, reason: 'beforeSend must be installed');
  return hook!(event, Hint()) as SentryEvent?;
}

void main() {
  group('the key predicate', () {
    test('denies the real field names this app handles', () {
      for (final key in [
        'customer_phone',
        'customer_name',
        'address_line',
        'place_name',
        'landmark',
        'national_id',
        'base_salary_piastres',
        'emergency_contact_phone',
        'check_in_latitude',
        'customer_lat',
        'Authorization',
        'pin_hash',
      ]) {
        expect(isPiiKey(key), isTrue, reason: '$key must be denied');
      }
    });

    test('matches short forms exactly and only exactly', () {
      // A teller login carries `pin=`, a delivery verification carries `otp=`.
      for (final key in ['pass', 'PIN', 'otp', 'lat', 'lng', 'user', 'owner', 'key']) {
        expect(isPiiKey(key), isTrue, reason: 'short form $key must be denied');
      }
      // ...and as substrings each of these would be a disaster.
      for (final key in [
        'bypass',
        'passed',
        'translate',
        'latency',
        'keyboard',
        'user_agent',
        'pinned',
        'uuid',
      ]) {
        expect(isPiiKey(key), isFalse, reason: '$key must NOT be denied');
      }
    });

    test('allowlists a machine word for itself but not a person label', () {
      // Without this the `name` fragment redacts the SDK's own metadata.
      expect(isPiiPath('os', 'name'), isFalse);
      expect(isPiiPath('sdk', 'name'), isFalse);
      expect(isPiiPath('runtime', 'name'), isFalse);
      // "Ali's iPad" is exactly what this file exists to stop.
      expect(isPiiPath('device', 'name'), isTrue);
      expect(isPiiKey('name'), isTrue);
    });

    test('lets ordinary domain keys through', () {
      // Over-redaction produces events that arrive, look fine, and cannot be
      // acted on.
      for (final key in [
        'order_id',
        'branch_id',
        'status',
        'line_cost',
        'quantity',
        'total_amount',
        'shift_id',
        'till_id',
        'retry_count',
      ]) {
        expect(isPiiKey(key), isFalse, reason: '$key must NOT be denied');
      }
    });
  });

  group('the message sanitizer', () {
    test('redacts labelled values and keeps the key', () {
      // Keeping the key is the point: the message still says which field was
      // involved, so the event stays actionable.
      expect(
        scrubText('no customer for phone=+201000000000 in branch 7'),
        'no customer for phone=$redacted in branch 7',
      );
      expect(
        scrubText('Employee { national_id: 29001011234567, id: 4 }'),
        'Employee { national_id: $redacted, id: 4 }',
      );
    });

    test('redacts a URL query per key without losing the rest', () {
      final out = scrubText(
        'POST https://api.madar-pos.cloud/orders?phone=%2B201000000000&branch_id=7 failed',
      );
      expect(out, contains('phone=$redacted'));
      // The non-sensitive parameter survives, so the request stays identifiable.
      expect(out, contains('branch_id=7'));
      expect(out, isNot(contains('201000000000')));
    });

    test('redacts credentials, emails and phone-shaped runs', () {
      expect(
        scrubText('rejected Bearer eyJhbGciOiJIUzI1NiJ9.abc.def'),
        'rejected Bearer $redacted',
      );
      expect(scrubText('could not notify ali@example.com'), 'could not notify $redacted');
      expect(scrubText('rang 01000000000 twice'), isNot(contains('01000000000')));
    });

    test('leaves ordinary diagnostics unchanged', () {
      // The direction that decides whether this is a sanitizer or just an
      // expensive way to send empty messages.
      for (final message in [
        'SocketException: Connection refused (OS Error: Connection refused, errno = 61)',
        'FormatException: Unexpected character at position 3',
        'order MDR-260831-0042 not found',
        'total_amount 16300 exceeds limit 1000000',
        'RangeError (index): Invalid value: Not in inclusive range 0..4: 7',
      ]) {
        expect(scrubText(message), message, reason: 'an ordinary diagnostic was mangled');
      }
    });

    test('is idempotent', () {
      final once = scrubText('phone=+201000000000');
      expect(scrubText(once), once);
    });
  });

  group('the captured event', () {
    SentryEvent buildEvent() => SentryEvent(
          message: SentryMessage('failed for customer_phone=+201000000000'),
          user: SentryUser(id: 'u1', email: 'a@b.c', username: 'ali'),
          serverName: 'alis-till',
          request: SentryRequest(
            url: 'https://api.madar-pos.cloud/orders?customer_phone=%2B201000000000',
            method: 'POST',
            headers: const {'authorization': 'Bearer secret-token'},
          ),
          tags: const {'address_line': '12 Main St', 'branch_id': '7'},
          breadcrumbs: [
            Breadcrumb(
              message: 'looking up phone=+201000000000',
              data: const {'national_id': '123', 'status': 500},
            ),
          ],
          exceptions: [
            SentryException(
              type: 'AnyhowException',
              value: 'no customer for phone=+201000000000',
            ),
          ],
        );

    test('clears identity outright and strips the request payload', () {
      final event = throughBeforeSend(buildEvent())!;
      // Not reduced to an opaque id — removed, so the privacy claim does not
      // depend on the SDK's definition of "default".
      expect(event.user, isNull);
      expect(event.serverName, isNull);
      expect(event.request?.url, 'https://api.madar-pos.cloud/orders');
      expect(event.request?.headers, isEmpty);
    });

    test('leaves nothing sensitive anywhere in the event', () {
      // Asserted over the whole serialized form, because inspecting one field
      // at a time is how a leak in the field you did not check survives.
      final wire = throughBeforeSend(buildEvent())!.toJson().toString();
      for (final leak in ['201000000000', '12 Main St', 'secret-token', 'a@b.c']) {
        expect(wire, isNot(contains(leak)), reason: 'event leaked $leak');
      }
    });

    test('still says what went wrong', () {
      final event = throughBeforeSend(buildEvent())!;
      expect(event.exceptions!.first.value, contains('no customer for'));
      expect(event.tags!['branch_id'], '7');
      expect(event.breadcrumbs!.first.data!['status'], 500);
      expect(event.breadcrumbs!.first.data!['national_id'], redacted);
    });
  });

  group('the option set', () {
    late SentryFlutterOptions options;

    setUp(() {
      options = SentryFlutterOptions()..dsn = 'https://public@example.invalid/2';
      configureSentryOptions(options);
    });

    test('never volunteers personal data', () {
      expect(options.sendDefaultPii, isFalse);
      // Both capture whatever is on screen and neither is reachable by a
      // key-based scrubber, so both are pinned off rather than left to a
      // default a future release could flip.
      expect(options.attachScreenshot, isFalse);
      // The option is marked experimental upstream; asserting on it is the
      // whole point, since it is what a future SDK release could flip.
      // ignore: experimental_member_use
      expect(options.attachViewHierarchy, isFalse);
      expect(options.enableUserInteractionBreadcrumbs, isFalse);
    });

    test('records replays only for errored sessions, fully masked', () {
      expect(options.replay.sessionSampleRate, 0.0);
      expect(options.replay.onErrorSampleRate, 1.0);
      expect(options.privacy.maskAllText, isTrue);
      expect(options.privacy.maskAllImages, isTrue);
      expect(options.replay.networkDetailAllowUrls, isEmpty);
    });

    test('propagates trace headers only to the Madar API', () {
      // The SDK default is `['.*']` — every outgoing request, third parties
      // included. Left alone that is an outward leak of our trace ids.
      expect(options.tracePropagationTargets, isNot(contains('.*')));
      expect(options.tracePropagationTargets.length, 1);
      expect(options.tracePropagationTargets.first, contains('madar-pos'));
    });

    test('installs both scrubbing hooks', () {
      // Breadcrumbs are scrubbed as they are RECORDED as well as when they are
      // sent: the SDK mirrors them onto the native scope, where the send-time
      // hook would never see them.
      expect(options.beforeSend, isNotNull);
      expect(options.beforeBreadcrumb, isNotNull);
    });
  });

  group('cross-surface parity', () {
    test('holds the same three lists the other surfaces do', () {
      // A cheap local guard; `scripts/check-scrub-parity.sh` in the backend
      // repo is the one that diffs the three files and fails on drift.
      expect(piiKeyDenylist.length, greaterThan(40));
      expect(piiKeyExact, contains('pass'));
      expect(piiKeyExact, contains('lat'));
      expect(piiKeyAllowlist, contains('os.name'));
      expect(piiKeyAllowlist, isNot(contains('device.name')));
      // Every entry is lowercase, or the case-insensitive comparisons silently
      // stop matching.
      for (final entry in [...piiKeyDenylist, ...piiKeyExact, ...piiKeyAllowlist]) {
        expect(entry, entry.toLowerCase());
      }
    });
  });
}
