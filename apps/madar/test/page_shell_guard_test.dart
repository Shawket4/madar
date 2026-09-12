// Every page in the product is framed by ONE shell, `MadarPageScaffold`,
// which owns the only `Scaffold` and the only safe-area decision. A raw
// `Scaffold(` anywhere else is a page that guesses its own insets again —
// the bug that put sign-in, the splash and a table's Sell under the clock.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/boot.dart';

/// The workspace root, from this package's test working directory.
const _root = '../..';

void main() {
  test('no page builds its own Scaffold outside the page shell', () {
    final offenders = <String>[];
    for (final top in ['apps', 'packages']) {
      final dir = Directory('$_root/$top');
      for (final f
          in dir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') ||
            !path.contains('/lib/') ||
            path.contains('/build/') ||
            path.contains('/.dart_tool/') ||
            path.contains('/ephemeral/') ||
            path.contains('/.symlinks/') ||
            path.contains('/generated/') ||
            path.endsWith('design_system/lib/src/page.dart')) {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          if (RegExp(r'(^|[^A-Za-z_.])Scaffold\(').hasMatch(line)) {
            offenders.add('$path:${i + 1}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use MadarPageScaffold instead');
  });

  test('a failed boot never shows a raw key for Retry', () {
    expect(bootRetryFallback('en'), 'Retry');
    expect(bootRetryFallback('ar'), 'إعادة المحاولة');
    expect(bootRetryFallback(), isNot('sync.retry'));
  });
}
