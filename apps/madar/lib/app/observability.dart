/// Crash/error reporting for the cashier app, against the SELF-HOSTED
/// Sentry at `sentry.madar-pos.cloud` (project 2).
///
/// Everything here is written around two hard constraints:
///
///  1. **The POS is offline-first.** A terminal that cannot reach the
///     internet must behave EXACTLY as it does today. Sentry is therefore
///     never awaited on a user path, never gates boot, and its own
///     failures are swallowed — see [initObservability].
///  2. **The published privacy policy says error reports exclude personal
///     data.** This app handles customer names, phone numbers and delivery
///     addresses plus staff identities, so the default "best effort"
///     reporting posture is not acceptable. `sendDefaultPii` is off AND a
///     [_beforeSend] / [_beforeBreadcrumb] pair scrubs anything that slips
///     through in free text. See [scrubText] for the WHY per rule.
///
/// # Keep the redaction lists identical across all three surfaces
///
/// [piiKeyDenylist], [piiKeyExact] and [piiKeyAllowlist] also exist in the
/// Rust backend (`src/observability/scrub.rs`) and the web dashboard
/// (`src/lib/sentry-scrub.ts`). They will drift unless something fails when
/// they do — see `scripts/check-scrub-parity.sh` in the backend repo, which is
/// wired into `preflight.sh` and CI.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException, PanicException;
import 'package:sentry_flutter/sentry_flutter.dart';

/// The DSN, supplied at build time:
/// `flutter build --dart-define=SENTRY_DSN=https://…@sentry.madar-pos.cloud/2`
///
/// Default is EMPTY on purpose: a build that was not given a DSN runs with
/// reporting fully disabled rather than silently pointing somewhere wrong.
/// Nothing anywhere may assume a client exists.
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// Mirrors `boot.dart`'s `MADAR_ENV` so an event's `environment` matches the
/// backend the terminal is actually talking to (one define drives both).
const _environment = String.fromEnvironment('MADAR_ENV', defaultValue: 'prod');

/// `release` groups events + marks regressions in Sentry. Defaults to the
/// pubspec version; CI should pass the real build id
/// (`--dart-define=SENTRY_RELEASE=madar@0.1.0+42`) so a release maps 1:1 to
/// an artifact.
///
/// Release stack traces are unreadable without symbols, so CI must also upload
/// them — `sentry-cli debug-files upload` for the native layers and
/// `flutter_symbols`/`--split-debug-info` output for Dart AOT. A build that
/// ships without them produces obfuscated frames nobody can act on.
const _release = String.fromEnvironment(
  'SENTRY_RELEASE',
  defaultValue: 'madar@0.1.0',
);

/// The API host this app's Rust core talks to, used to scope trace
/// propagation. Supplied at build time alongside `MADAR_ENV`.
const _apiHost = String.fromEnvironment(
  'MADAR_API_HOST',
  defaultValue: 'api.madar-pos.cloud',
);

/// Whether this build reports at all. Exposed so callers can skip the whole
/// Sentry code path (and its zone) when the DSN was never provided.
bool get sentryEnabled => sentryDsn.isNotEmpty;

/// Boots [runner] with Sentry wrapped around it when a DSN is configured,
/// and boots it plainly otherwise.
///
/// [runner] is guaranteed to run EXACTLY ONCE, even if `SentryFlutter.init`
/// throws (bad DSN, unwritable cache dir, native SDK failure). Losing crash
/// reporting is an inconvenience; a till that will not open is a business
/// outage — the app always wins that trade.
///
/// `SentryFlutter.init(appRunner:)` installs `FlutterError.onError` and
/// `PlatformDispatcher.instance.onError` itself — they catch different
/// failures (framework errors versus uncaught async errors on the root zone),
/// and both are covered by going through `appRunner`. What it does NOT cover is
/// a spawned isolate, which is why [_listenForIsolateErrors] exists.
Future<void> initObservability(FutureOr<void> Function() runner) async {
  if (!sentryEnabled) {
    await runner();
    return;
  }
  var started = false;
  Future<void> runOnce() async {
    if (started) return;
    started = true;
    _listenForIsolateErrors();
    await runner();
  }

  try {
    await SentryFlutter.init(configureSentryOptions, appRunner: runOnce);
  } on Object {
    // Deliberately broad + silent: nothing about observability may prevent
    // the cashier app from starting.
  }
  await runOnce();
}

/// Report errors thrown inside spawned isolates.
///
/// Neither `FlutterError.onError` nor `PlatformDispatcher.onError` sees these:
/// an isolate has its own error zone, so background work fails silently exactly
/// the way an unguarded server task does. This app moves receipt rendering and
/// sync batches off the UI isolate, so that is real coverage, not a hypothetical.
///
/// The port is intentionally never closed — it lives as long as the process.
void _listenForIsolateErrors() {
  final port =
      RawReceivePort((dynamic pair) {
          // The payload is always `[error, stackTrace]`, both already stringified by
          // the isolate boundary.
          if (pair is! List || pair.length < 2) return;
          final error = pair.first;
          final stack = pair.last;
          // Fire-and-forget by construction: an isolate error report must never be
          // awaited on a code path that is already unwinding.
          unawaited(
            Sentry.captureException(
              error,
              stackTrace: stack is String
                  ? StackTrace.fromString(stack)
                  : stack,
              withScope: (scope) {
                scope
                  // A fingerprint that does not include the message, so a hundred
                  // variations of one failure stay one issue.
                  ..fingerprint = ['isolate', '$error'.split('\n').first]
                  // `setTag` returns `FutureOr<void>`; inside a synchronous scope
                  // callback there is nothing to await it on.
                  // ignore: discarded_futures
                  ..setTag('source', 'isolate');
              },
            ),
          );
        })
        // The port is deliberately never closed: it lives as long as the process.
        ..keepIsolateAlive = false;
  Isolate.current.addErrorListener(port.sendPort);
}

/// Name the current transaction after the ROUTE PATTERN.
///
/// This app has no `Navigator` routes — the shell swaps screens under a single
/// `MaterialApp.home` driven by the core's `AppRoute` — so
/// `SentryNavigatorObserver` would only ever see the root route. Passing the
/// route's *type* name here is the equivalent, and it is a pattern by
/// construction: it can never carry an order id or a table number, so it cannot
/// produce one transaction group per record.
///
/// Call it from the shell whenever the route changes. A no-op when Sentry is
/// not configured.
void setRouteTransaction(String routePattern) {
  if (!sentryEnabled) return;
  // Naming the scope is best effort and must never block a build().
  // `configureScope` returns `FutureOr<void>`, so it is awaited only when the
  // SDK actually hands back a future.
  final pending = Sentry.configureScope(
    (scope) => scope.transaction = routePattern,
  );
  if (pending is Future<void>) unawaited(pending);
}

/// The option set. Split out (and public) so it can be exercised in tests
/// without standing up the real SDK.
void configureSentryOptions(SentryFlutterOptions options) {
  options
    ..dsn = sentryDsn
    ..environment = _environment
    ..release = _release
    // Performance is a nice-to-have here, and every span is bytes over a
    // till's often-metered link — sample it down hard. Errors are NOT
    // sampled; they all go.
    ..tracesSampleRate = 0.02
    // ---- OFFLINE DURABILITY -------------------------------------------
    // The native layers (sentry-android / sentry-cocoa / sentry-native)
    // persist outgoing envelopes to disk and replay them on the next
    // launch or when the transport recovers, so a terminal that crashes
    // mid-service with no WAN still reports once it is back. That caching
    // is ON by default; the default depth is only 30 envelopes, which a
    // branch that has been offline for a full trading day can overrun.
    // Raise it, and keep native crash handling explicitly on since it is
    // what produces the events being cached.
    ..maxCacheItems = 200
    ..enableNativeCrashHandling = true
    // ---- PII: DENY BY DEFAULT ------------------------------------------
    // COMPLIANCE CONTROL. The published privacy policy states that error
    // reports exclude personal data. `sendDefaultPii = false` stops the SDK
    // volunteering IP address, device name and user identity.
    ..sendDefaultPii = false
    // A POS screen is a live view of a customer's name, phone and delivery
    // address, and the widget tree carries the same strings. Neither may
    // ever be attached to an event, and neither is reachable by a key-based
    // scrubber — so both are pinned off explicitly rather than left to a
    // default that a future SDK release could flip.
    ..attachScreenshot = false
    // Pinned deliberately: the default is already false, and stating it here
    // means a future SDK release cannot flip it silently on an app whose widget
    // tree is full of customer names.
    // ignore: experimental_member_use
    ..attachViewHierarchy = false
    // Tap breadcrumbs are labelled from the widget under the finger — on
    // this app that label is frequently a customer or staff name. The
    // debugging value does not justify shipping identities.
    ..enableUserInteractionBreadcrumbs = false
    ..enableUserInteractionTracing = false
    // Last line of defence over everything the SDK still assembles.
    ..beforeSend = _beforeSend
    ..beforeBreadcrumb = _beforeBreadcrumb;

  // ---- TRACE PROPAGATION --------------------------------------------
  // The Dart SDK's default is `['.*']` — it attaches `sentry-trace` and
  // `baggage` to EVERY outgoing request, including third parties. That is the
  // opposite hazard from the browser SDK's same-origin default: here the risk
  // is leaking our trace ids outward, not failing to propagate. Narrow it to
  // the Madar API.
  //
  // KNOWN GAP, stated rather than hidden: this app makes no HTTP calls from
  // Dart at all — every request goes through the Rust core over
  // flutter_rust_bridge — so nothing here currently propagates a trace to the
  // backend. Closing that needs the core to inject the headers itself, which
  // is a change in `madar/rust-core`, outside this file. This setting makes
  // the Dart side correct for any request the SDK does instrument, and stops
  // the permissive default from becoming a leak the day one is added.
  options.tracePropagationTargets
    ..clear()
    ..add(RegExp.escape(_apiHost));

  // ---- SESSION REPLAY ------------------------------------------------
  // Off for ordinary sessions, kept only for sessions that errored — and
  // fully masked either way. A replay of a POS screen is a recording of a
  // customer's name, phone and address; masking is what makes it a layout
  // artefact rather than a data export.
  options.replay.sessionSampleRate = 0.0;
  options.replay.onErrorSampleRate = 1.0;
  options.privacy.maskAllText = true;
  options.privacy.maskAllImages = true;
  // No URL is worth recording request/response bodies for on an app whose
  // every endpoint returns customer data, and a recorded body is not
  // reachable by a key-based scrubber.
  options.replay.networkDetailAllowUrls.clear();
}

/// Strips/redacts personal data from an event immediately before it leaves
/// the device, and tags Rust-core failures so they are triageable.
///
/// This runs on Dart-originated events. Events produced entirely inside the
/// native crash handlers (a hard SIGSEGV in the platform layer) are
/// assembled and sent natively and do NOT pass through here — which is why
/// the options above stop PII reaching the native scope in the first place
/// rather than relying on this hook alone.
SentryEvent? _beforeSend(SentryEvent event, Hint hint) {
  // A Rust panic surfaces in Dart as an FRB PanicException / AnyhowException.
  // Tagging is free and no bridge regeneration is involved: these types are
  // already thrown by the existing generated bindings.
  final throwable = event.throwable;
  if (throwable is PanicException || throwable is AnyhowException) {
    event.tags = {...?event.tags, 'source': 'rust_core'};
  }

  // Identity is dropped OUTRIGHT rather than reduced to an id. Trimming
  // individual fields leaves the privacy claim depending on the SDK's
  // definition of "default", which a future release is free to widen;
  // removing the whole context does not. Correlation is preserved by the
  // `source` / route tags, which are not personal data.
  event.user = null;

  // A request URL can carry a phone number as a path/query segment (customer
  // lookup) and headers carry the session token. Keep the shape, drop the
  // payload.
  final request = event.request;
  if (request != null) {
    final url = request.url;
    event.request = SentryRequest(
      url: url == null ? null : scrubText(url.split('?').first),
      method: request.method,
    );
  }

  // Free text: exception messages and log messages routinely interpolate the
  // offending value ("no customer for +2010…"). This is the part the
  // key-based rules can never reach.
  final message = event.message;
  if (message != null) {
    message
      ..formatted = scrubText(message.formatted)
      ..params = message.params?.map(_scrubValue).toList();
  }
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    exception.value = scrubText(exception.value ?? '');
  }
  event
    // `serverName` is the device hostname, which branches routinely set to a
    // staff member's name — treat it as PII and drop it outright.
    ..serverName = null
    ..breadcrumbs = event.breadcrumbs?.map(_scrubBreadcrumb).toList()
    ..tags = event.tags?.map(
      (key, value) =>
          MapEntry(key, isPiiKey(key) ? _redacted : scrubText(value)),
    )
    // `extra` is deprecated upstream in favour of structured contexts, but
    // any event that still carries it must be scrubbed like everything else.
    // ignore: deprecated_member_use
    ..extra = _scrubMap(event.extra);
  return event;
}

/// Breadcrumbs are scrubbed as they are RECORDED, not just as they are sent:
/// the SDK mirrors them onto the native scope, where the send-time hook above
/// would never see them.
Breadcrumb? _beforeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  return breadcrumb == null ? null : _scrubBreadcrumb(breadcrumb);
}

Breadcrumb _scrubBreadcrumb(Breadcrumb crumb) {
  final message = crumb.message;
  return crumb
    ..message = message == null ? null : scrubText(message)
    ..data = _scrubMap(crumb.data);
}

const _redacted = '[redacted]';

// ─────────────────────────────────────────────────────────────────────────────
// The three matching rules, in order. Identical to the backend and the
// dashboard — see the library docs.
// ─────────────────────────────────────────────────────────────────────────────

/// Case-insensitive **substring** matches.
///
/// Written from the personal data this system actually handles: customer
/// names, phones and delivery addresses; staff identities, national ids and
/// pay; and every credential (PIN hashes, bearer tokens, delivery OTPs).
const piiKeyDenylist = <String>[
  // Contact details
  'phone',
  'mobile',
  'msisdn',
  'whatsapp',
  'email',
  // Deliberately broad — `customer_name`, `place_name` and
  // `emergency_contact_name` are all personal data here. The allowlist is what
  // keeps this from eating `os.name`.
  'name',
  'customer',
  'recipient',
  // Addresses and geography
  'address',
  'street',
  'building',
  'apartment',
  'landmark',
  'postcode',
  'zipcode',
  'latitude',
  'longitude',
  'coordinate',
  'geolocation',
  // Government identity and pay
  'national_id',
  'nationalid',
  'passport',
  'salary',
  'wage',
  'payslip',
  'payroll',
  // Credentials
  'password',
  'passwd',
  'passphrase',
  'secret',
  'token',
  'credential',
  'cookie',
  'jwt',
  'bearer',
  'api_key',
  'apikey',
  'authorization',
  'signature',
  'private_key',
  'privatekey',
  'pin_hash',
  'pinhash',
  'otp_code',
  'sessionid',
  'session_token',
  // Payment instruments
  'iban',
  'card_number',
  'cardnumber',
];

/// Case-insensitive **equality** matches — short forms a substring rule cannot
/// safely express.
///
/// A teller login carries `pin=`, a delivery verification carries `otp=`, and a
/// geofence fix carries `lat=` / `lng=`. Every one is missed by the longer
/// spellings above.
///
/// They must stay EXACT. As substrings `pass` eats `bypass`, `lat` eats
/// `translate`, `key` eats `keyboard` and `user` eats `user_agent` — each of
/// which quietly destroys the debugging value of an event while protecting
/// nothing.
const piiKeyExact = <String>[
  'pass',
  'pin',
  'otp',
  'lat',
  'lng',
  'lon',
  'ssn',
  'nid',
  'dob',
  'tel',
  'addr',
  'key',
  'auth',
  'user',
  'owner',
  'uid',
  'cvv',
  'cvc',
  'gps',
  'pwd',
];

/// Checked **before** the denylist. Keys whose value is a machine describing
/// itself, not a person. Matched as `parent.key`.
///
/// `device.name` is deliberately absent: that is a person's own label for their
/// device, which is exactly the data this file exists to stop.
const piiKeyAllowlist = <String>[
  'os.name',
  'runtime.name',
  'browser.name',
  'sdk.name',
  'job.name',
  'app.name',
  'package.name',
  'integration.name',
  'transaction.name',
  'span.name',
  'event.name',
  'device.family',
  'device.model',
];

final String _piiKeyFragmentsAlt = [
  ...piiKeyDenylist,
  ...piiKeyExact,
].join('|');

/// True when a key must be redacted, given the key of the object containing it.
bool isPiiPath(String? parent, String key) {
  final k = key.toLowerCase();
  // 1. Allowlist first, or the `name` fragment eats the SDK's own metadata.
  if (parent != null &&
      piiKeyAllowlist.contains('${parent.toLowerCase()}.$k')) {
    return false;
  }
  if (piiKeyAllowlist.contains(k)) return false;
  // 2. Exact short forms.
  if (piiKeyExact.contains(k)) return true;
  // 3. Substrings.
  return piiKeyDenylist.any(k.contains);
}

/// True when a key must be redacted, ignoring any parent context.
bool isPiiKey(String key) => isPiiPath(null, key);

Map<String, dynamic>? _scrubMap(Map<String, dynamic>? map, [String? parent]) {
  if (map == null) return null;
  return map.map(
    (key, value) => MapEntry(
      key,
      isPiiPath(parent, key) ? _redacted : _scrubValue(value, key),
    ),
  );
}

dynamic _scrubValue(dynamic value, [String? parent]) {
  if (value is String) return scrubText(value);
  if (value is Map<String, dynamic>) return _scrubMap(value, parent);
  if (value is List) return value.map((v) => _scrubValue(v, parent)).toList();
  return value;
}

// An e-mail anywhere in free text is personal data by definition.
final _emailPattern = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

/// Phone-SHAPED runs, allowing the spaces/dashes/parens people type them
/// with. The match is intentionally loose and then confirmed by
/// [_looksLikePhoneNumber] — a bare regex over "8+ digits" also eats order
/// refs (`MDR-260831-0042`), timestamps and totals, and a stripped stack
/// trace is a stack trace we cannot act on.
final _phonePattern = RegExp(
  r'(?<![\w.])(?:\+|00)?\d[\d ()\-]{6,18}\d(?![\w.])',
);

/// `Bearer <token>` in free text, which the labelled rule cannot see because
/// there is no key.
final _authSchemePattern = RegExp(
  r'\b(bearer|basic|token)\s+[A-Za-z0-9\-._~+/=]{8,}',
  caseSensitive: false,
);

/// `key: value` / `key=value` pairs inside a `toString()`ed struct — this is
/// how Rust `Debug` output and Dart model `toString()`s leak fields that the
/// key-based map redaction never sees, because by then the whole struct is
/// one string. Runs BEFORE the shape-based rules so a labelled field is
/// redacted by its NAME (always correct) rather than by looking phone-ish.
///
/// `/` and `?` are delimiters specifically so a URL does not swallow itself:
/// without them the leading `https:` matches as a key and consumes the whole
/// URL as one value, and the `?phone=` inside it is never seen at all.
final _labelledPattern = RegExp(
  '(("?)(\\w*(?:$_piiKeyFragmentsAlt)\\w*)"?\\s*[:=]\\s*)'
  '("[^"]*"|\'[^\']*\'|\\[redacted\\]|[^,;&/?\\s>)}\\]"]+)',
  caseSensitive: false,
);

/// True when the digits of [raw] plausibly form a dialable number rather
/// than an id or a money amount. Tuned for Egypt (`01XXXXXXXXX`,
/// `+201XXXXXXXXX`) while still catching any internationally-prefixed run.
bool _looksLikePhoneNumber(String raw) {
  final prefixed = raw.startsWith('+') || raw.startsWith('00');
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 9 || digits.length > 15) return false;
  if (prefixed) return true;
  // Local form (leading 0) or the country code typed without a `+`.
  return digits.startsWith('0') || digits.startsWith('20');
}

/// Redact personal data **inside** a free-text string.
///
/// The tempting alternative is to withhold messages entirely, which is worse:
/// it leaves events with an operation name and no indication of what went
/// wrong. This keeps the key and replaces the value, so the message still says
/// which field was involved. Ordinary diagnostics must come through unchanged —
/// over-redaction produces events that arrive, look fine, and cannot be acted
/// on.
String scrubText(String input) {
  if (input.isEmpty) return input;
  return input
      .replaceAllMapped(_labelledPattern, (match) {
        final prefix = match.group(1)!;
        final key = match.group(3)!;
        final value = match.group(4)!;
        // Idempotent: the hook can run over already-scrubbed text, and a second
        // pass must not corrupt the marker into `[redacted]]`.
        if (value.startsWith(_redacted) || !isPiiKey(key))
          return match.group(0)!;
        return '$prefix$_redacted';
      })
      .replaceAllMapped(
        _authSchemePattern,
        (match) => '${match.group(1)} $_redacted',
      )
      .replaceAll(_emailPattern, _redacted)
      .replaceAllMapped(
        _phonePattern,
        (match) => _looksLikePhoneNumber(match.group(0)!)
            ? _redacted
            : match.group(0)!,
      );
}
