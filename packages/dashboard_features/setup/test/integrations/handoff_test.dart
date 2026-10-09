// The handoff after an issue or a rotation (SET-INT-020..028, 032).
import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/integrations/credential_util.dart';
import 'package:dashboard_setup/src/integrations/handoff_content.dart';
import 'package:dashboard_setup/src/integrations/handoff_dialog.dart';
import 'package:dashboard_setup/src/integrations/handoff_zip.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final Finder _handoff = find.byKey(const ValueKey('handoff-dialog'));
Finder _in(Finder f) => find.descendant(of: _handoff, matching: f);

final RegExp _passphraseShape = RegExp(
  r'^[2-9A-HJKMNP-Z]{4}(-[2-9A-HJKMNP-Z]{4}){4}$',
);

/// Rotates Rue's password as a platform admin: the handoff opens.
Future<DashHarness> _rotateRue(
  WidgetTester tester, {
  DashSize size = DashSize.desktop,
}) async {
  final h = await pumpIntegrations(
    tester,
    persona: Persona.platform,
    size: size,
  );
  final id = IntegrationsSeed.id('rue');
  await h.tap(find.byKey(ValueKey('integrations-rotate-$id')));
  await h.tap(top('Rotate'));
  expect(_handoff, findsOneWidget);
  return h;
}

/// The passphrase on screen.
String _shown(WidgetTester tester) => tester
    .widget<SelectableText>(
      _in(
        find.descendant(
          of: find.byKey(const ValueKey('handoff-passphrase')),
          matching: find.byType(SelectableText),
        ),
      ),
    )
    .data!;

DashButton _button(WidgetTester tester, String key) =>
    tester.widget<DashButton>(find.byKey(ValueKey(key)));

/// The archive's files, opened with [passphrase].
Map<String, String> _open(List<int> zip, String passphrase) {
  final archive = ZipDecoder().decodeBytes(zip, password: passphrase);
  return {for (final f in archive.files) f.name: utf8.decode(f.content)};
}

void main() {
  tearDown(HandoffZipBuilder.reset);

  testWidgets('SET-INT-020 a 20-symbol passphrase; the encrypted archive '
      'saved at once under its dated name', (tester) async {
    final h = await _rotateRue(tester);
    final passphrase = _shown(tester);
    expect(passphrase, matches(_passphraseShape));
    final saved = h.files.saved.single;
    // The mock's now is 2026-10-08 (UTC).
    expect(
      saved.filename,
      'madar-credentials-rue-one-ninety-k7m2xq-2026-10-08.zip',
    );
    expect(saved.mimeType, 'application/zip');
    final files = _open(saved.bytes, passphrase);
    expect(files.keys, ['README.txt', 'credentials.txt']);
    final creds = files['credentials.txt']!;
    expect(creds, contains('Issued for : Rue — One Ninety'));
    expect(creds, contains('Username   : rue-one-ninety-k7m2xq'));
    final secret = RegExp(
      r'Password   : ([0-9a-f]{64})',
    ).firstMatch(creds)![1]!;
    expect(creds, contains(basicAuthHeader('rue-one-ninety-k7m2xq', secret)));
    expect(files['README.txt'], isNot(contains(secret)));
    // The secret is never on screen.
    expect(find.textContaining(secret), findsNothing);
    expect(
      () => _open(saved.bytes, 'WRONG-PASS-WORD-XXXX-YYYY'),
      throwsA(anything),
    );
  });

  testWidgets('SET-INT-021 rotated: its title and hint; 560 wide', (
    tester,
  ) async {
    final h = await _rotateRue(tester);
    expect(_in(find.text('New password for Rue — One Ninety')), findsOneWidget);
    expect(
      _in(find.text(h.t('integrations.handoff.rotatedHint'))),
      findsOneWidget,
    );
    expect(handoffDialogWidth, 560);
    expect(tester.getSize(_handoff).width, lessThanOrEqualTo(560));
  });

  testWidgets('SET-INT-022 SET-INT-025 while building: "Preparing…", Copy '
      'and Download again disabled', (tester) async {
    final build = Completer<List<int>>();
    HandoffZipBuilder.build = (files, p) => build.future;
    final h = await _rotateRue(tester);
    expect(_shown(tester), 'Preparing…');
    expect(
      tester
          .widget<DashIconButton>(find.byKey(const ValueKey('handoff-copy')))
          .onPressed,
      isNull,
    );
    expect(_button(tester, 'handoff-download').loading, isTrue);
    expect(h.files.saved, isEmpty);
    build.complete(const [1, 2, 3]);
    await h.settle();
    expect(_shown(tester), matches(_passphraseShape));
    expect(_button(tester, 'handoff-download').loading, isFalse);
    expect(_button(tester, 'handoff-download').onPressed, isNotNull);
    expect(h.files.saved.single.bytes, [1, 2, 3]);
  });

  testWidgets('SET-INT-022 Copy puts the passphrase on the clipboard and '
      'shows a check for 1.5 s', (tester) async {
    final clipboard = FakeClipboard(tester);
    final h = await _rotateRue(tester);
    await h.tap(find.byKey(const ValueKey('handoff-copy')));
    expect(clipboard.text, _shown(tester));
    DashIconButton copy() =>
        tester.widget(find.byKey(const ValueKey('handoff-copy')));
    expect(copy().icon, 'check');
    await tester.pump(const Duration(milliseconds: 1600));
    expect(copy().icon, 'copy');
    expect(copy().semanticLabel, 'Copy');
  });

  testWidgets('SET-INT-022 a refused copy toasts how to copy by hand', (
    tester,
  ) async {
    final clipboard = FakeClipboard(tester)..refuse = true;
    final h = await _rotateRue(tester);
    await h.tap(find.byKey(const ValueKey('handoff-copy')));
    expect(clipboard.text, isNull);
    await h.expectToast(h.t('integrations.handoff.copyFailed'));
  });

  testWidgets('SET-INT-023 the three steps and the warning', (tester) async {
    final h = await _rotateRue(tester);
    for (final k in ['step1', 'step2', 'step3', 'warning']) {
      expect(_in(find.text(h.t('integrations.handoff.$k'))), findsOneWidget);
    }
    expect(_in(find.text(ltr('1.'))), findsOneWidget);
    expect(_in(find.text(ltr('3.'))), findsOneWidget);
  });

  testWidgets('SET-INT-024 SET-INT-032 a failed build: the red panel; Try '
      'again rebuilds with the same passphrase and saves', (tester) async {
    final used = <String>[];
    HandoffZipBuilder.build = (files, p) async {
      used.add(p);
      if (used.length == 1) throw StateError('disk full');
      return const [9, 9];
    };
    final h = await _rotateRue(tester);
    final panel = find.byKey(const ValueKey('handoff-failed'));
    expect(
      find.descendant(
        of: panel,
        matching: find.text(
          'The credential was created, but the file could not be built.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text(h.t('integrations.handoff.failedHint')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text(h.t('errors.unknown'))),
      findsOneWidget,
    );
    expect(_button(tester, 'handoff-download').onPressed, isNull);
    expect(h.files.saved, isEmpty);
    await h.tap(find.byKey(const ValueKey('handoff-retry')));
    expect(used, hasLength(2));
    expect(used[1], used[0]);
    expect(_shown(tester), used[0]);
    expect(h.files.saved, hasLength(1));
    // The retry's save counts: Done closes without asking.
    await h.tap(find.byKey(const ValueKey('handoff-done')));
    expect(_handoff, findsNothing);
  });

  testWidgets('SET-INT-025 Download again saves the same file again', (
    tester,
  ) async {
    final h = await _rotateRue(tester);
    await h.tap(find.byKey(const ValueKey('handoff-download')));
    expect(h.files.saved, hasLength(2));
    expect(h.files.saved[1].filename, h.files.saved[0].filename);
    expect(h.files.saved[1].bytes, h.files.saved[0].bytes);
  });

  testWidgets('SET-INT-026 never saved: Done and Escape ask "Close without '
      'the file?"; Cancel stays, Close anyway closes', (tester) async {
    final h = await pumpIntegrations(tester, persona: Persona.platform);
    h.files.cancelNextSave = true;
    await h.tap(
      find.byKey(ValueKey('integrations-rotate-${IntegrationsSeed.id('rue')}')),
    );
    await h.tap(top('Rotate'));
    expect(h.files.saved, isEmpty);
    await h.tap(find.byKey(const ValueKey('handoff-done')));
    expect(top('Close without the file?'), findsOneWidget);
    expect(top(h.t('integrations.handoff.closeHint')), findsOneWidget);
    await h.tap(top('Cancel'));
    expect(_handoff, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(top('Close without the file?'), findsOneWidget);
    await h.tap(top('Close anyway'));
    expect(_handoff, findsNothing);
    expect(top('Close without the file?'), findsNothing);
  });

  testWidgets('SET-INT-026 saved after all with Download again: Done closes', (
    tester,
  ) async {
    final h = await pumpIntegrations(tester, persona: Persona.platform);
    h.files.cancelNextSave = true;
    await h.tap(
      find.byKey(ValueKey('integrations-rotate-${IntegrationsSeed.id('rue')}')),
    );
    await h.tap(top('Rotate'));
    await h.tap(find.byKey(const ValueKey('handoff-download')));
    expect(h.files.saved, hasLength(1));
    await h.tap(find.byKey(const ValueKey('handoff-done')));
    expect(_handoff, findsNothing);
  });

  testWidgets('SET-INT-020 phone: the handoff fills the screen', (
    tester,
  ) async {
    await _rotateRue(tester, size: DashSize.phone);
    expect(_shown(tester), matches(_passphraseShape));
    expect(_in(find.text('Done')), findsOneWidget);
  });

  group('the files', () {
    HandoffInput input({
      HandoffMode mode = HandoffMode.created,
      String label = 'Rue — One Ninety',
      String branch = 'Zamalek',
    }) => HandoffInput(
      label: label,
      username: 'rue-one-ninety-k7m2',
      secret: 's3cret-partner-token',
      branchName: branch,
      issuedAt: DateTime.utc(2026, 8, 4, 9, 30),
      mode: mode,
      apiBase: 'https://api.example.test/',
    );
    String named(List<HandoffFile> files, String name) =>
        files.firstWhere((f) => f.name == name).text;

    test('SET-INT-027 credentials.txt: who, where, when, the login, the '
        'endpoint, the header and a curl', () {
      final files = buildHandoffFiles(input());
      expect(files.map((f) => f.name), ['README.txt', 'credentials.txt']);
      final text = named(files, 'credentials.txt');
      expect(text, contains('Issued for : Rue — One Ninety\r\n'));
      expect(text, contains('Branch     : Zamalek\r\n'));
      expect(text, contains('Issued on  : 2026-08-04T09:30:00.000Z\r\n'));
      expect(text, contains('Username   : rue-one-ninety-k7m2\r\n'));
      expect(text, contains('Password   : s3cret-partner-token\r\n'));
      const endpoint =
          'https://api.example.test/integrations/analytics/orders'
          '?from=YYYY-MM-DD&to=YYYY-MM-DD';
      expect(text, contains('$endpoint\r\n'));
      expect(
        text,
        contains(
          'Basic ${'cnVlLW9uZS1uaW5ldHktazdtMjpzM2NyZXQtcGFydG5lci10b2tlbg=='}',
        ),
      );
      expect(
        text,
        contains(
          "curl -u 'rue-one-ninety-k7m2:s3cret-partner-token' \\\r\n"
          "  'https://api.example.test/integrations/analytics/orders"
          "?from=2026-08-04&to=2026-08-04'\r\n",
        ),
      );
    });

    test('SET-INT-028 README.txt: the guide, without the secret; a rotation '
        'says so first', () {
      final created = named(buildHandoffFiles(input()), 'README.txt');
      final rotated = named(
        buildHandoffFiles(input(mode: HandoffMode.rotated)),
        'README.txt',
      );
      expect(created, isNot(contains('s3cret-partner-token')));
      expect(created, startsWith('MADAR ANALYTICS API - INTEGRATION GUIDE'));
      expect(created, contains('new credentials for the Madar Analytics API'));
      expect(rotated, contains('REPLACEMENT password'));
      expect(rotated, contains('previous password stopped'));
      expect(
        created,
        contains(
          'GET https://api.example.test/integrations/'
          'analytics/orders\r\n',
        ),
      );
      for (final s in ['Africa/Cairo', '429', '401', '400']) {
        expect(created, contains(s));
      }
    });

    test('SET-INT-027 SET-INT-028 CRLF, no BOM, non-ASCII carried', () {
      final files = buildHandoffFiles(
        input(label: 'وان ناينتي', branch: 'الزمالك'),
      );
      for (final f in files) {
        expect(f.name, matches(RegExp(r'^[\x20-\x7E]+$')));
        expect(f.text.startsWith('﻿'), isFalse);
        expect(f.text, contains('\r\n'));
        expect(f.text.replaceAll('\r\n', ''), isNot(contains('\n')));
      }
      expect(named(files, 'credentials.txt'), contains('وان ناينتي'));
      expect(named(files, 'credentials.txt'), contains('الزمالك'));
    });

    test('SET-INT-020 the file name: dated, slugged, never a path', () {
      expect(
        handoffFilename('rue-one-ninety-k7m2', DateTime.utc(2026, 8, 4, 9, 30)),
        'madar-credentials-rue-one-ninety-k7m2-2026-08-04.zip',
      );
      final odd = handoffFilename('../مدار/x', DateTime.utc(2026, 8, 4));
      expect(
        odd,
        matches(RegExp(r'^madar-credentials-[a-z0-9-]*-2026-08-04\.zip$')),
      );
      expect(
        handoffFilename('مدار', DateTime.utc(2026, 8, 4)),
        'madar-credentials-partner-2026-08-04.zip',
      );
    });

    test('SET-INT-020 the archive opens with its passphrase only (WinZip '
        'AES-256)', () {
      final files = buildHandoffFiles(input());
      final zip = encryptedHandoffZip(files, 'ABCD-EFGH-JKMN-PQRS-TUVW');
      final opened = _open(zip, 'ABCD-EFGH-JKMN-PQRS-TUVW');
      expect(opened['credentials.txt'], named(files, 'credentials.txt'));
      // AE-x extra field with strength 3 (AES-256).
      final bytes = zip.toList();
      var found = false;
      for (var i = 0; i + 8 < bytes.length; i++) {
        if (bytes[i] == 0x01 &&
            bytes[i + 1] == 0x99 &&
            bytes[i + 6] == 0x41 &&
            bytes[i + 7] == 0x45) {
          expect(bytes[i + 8], 3);
          found = true;
          break;
        }
      }
      expect(found, isTrue);
      expect(() => _open(zip, 'WRONG'), throwsA(anything));
    });

    test('SET-INT-020 passphrases: the shape, the alphabet, rejection '
        'sampling', () {
      expect(passphraseAlphabet, '23456789ABCDEFGHJKMNPQRSTUVWXYZ');
      for (var i = 0; i < 50; i++) {
        expect(generatePassphrase(), matches(_passphraseShape));
      }
      // Bytes 248..255 are skipped, never folded onto the alphabet.
      var calls = 0;
      final p = generatePassphrase((buf) {
        calls++;
        for (var i = 0; i < buf.length; i++) {
          buf[i] = calls == 1 ? 250 : i % 31;
        }
      });
      expect(calls, 2);
      expect(p, '2345-6789-ABCD-EFGH-JKMN');
    });
  });
}
