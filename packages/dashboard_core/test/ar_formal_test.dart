// The dashboard's Arabic is formal (owner default #42): Egyptian colloquial
// stays in the staff app and on the customer pages, never on a dashboard
// screen. The web guards its own table (`src/i18n/ar-formal.test.ts`, the
// same markers); this one guards what the Flutter dashboard adds: the synced
// table and every area's supplement.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Customer-facing surfaces keep their own voice (the web's NOT_DASHBOARD).
const _notDashboard = {'menu', 'reservations', 'order'};

const _a = r'؀-ۿ';
const _nb = '(?<![$_a])';
const _na = '(?![$_a])';
const _words =
    'عايز|عايزة|عاوز|مش|ده|دي|دا|إزاي|ازاي|كده|كدا|مفيش|مافيش|مينفعش|'
    'لسه|دلوقتي|بتاع|بتاعت|بتاعك|بتاعه|بتاعنا|بتوع|بتوعه|خلاص|اللي|تاني|'
    'تانية|عشان|علشان|إنت|انت|برضه|بقى|إيه|ايه|فين|إمتى|امتى|زي|بس|مستني|'
    'ملوش|مالوش|محدش|كام|لمين|قصاد|النهارده|أنهي|بالظبط|استنى|سيب|وريها|'
    'حابب|يقدر|تقدر|نقدر|محتاج|محتاجة|كتير|ابعت|خلّي|خلي|يديك|يديهالك|'
    'ببلاش|غلط|اختار|فاضل|ماشي|القايمة|تلات';

/// اتـ passives, هـ futures and مـ…ش negations, with the formal words that
/// start the same way let through (the web's list).
const _passive =
    '$_nbات(?!جاه|صال|صل|فاق|خاذ|خذ|باع|ساق|ساع|حاد|ضح|جه|صف|سع|سم|هام|كال|زان|فق|رك|بع|حد)[$_a]{2,}';
const _future = '$_nbه(?!يئ|ناك|ندس|نا$_na)(?:ي|ت|ن)[$_a]{3,}';
const _negation = '$_nbم(?!شو|نع|فت|ده|رع|عا)[$_a]{2,}ش$_na';
const _phrases = '$_nb(?:قبل ما|بعد ما|أول ما|لحد ما)$_na';

final _markers = RegExp(
  '$_nb(?:$_words)$_na|$_phrases|$_passive|$_future|$_negation',
  unicode: true,
);

/// Diacritics (a shadda in اتّباع) don't change the word.
bool colloquial(String s) =>
    _markers.hasMatch(s.replaceAll(RegExp('[ً-ْ]'), ''));

Iterable<(String, String)> _strings(Object? node, [String prefix = '']) sync* {
  if (node is String) {
    yield (prefix, node);
  } else if (node is Map) {
    for (final e in node.entries) {
      yield* _strings(
        e.value,
        prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}',
      );
    }
  }
}

void main() {
  test('the guard catches the colloquial and passes the formal', () {
    for (final s in [
      'اتضاف الموظف. هيدخل بكود على الواتساب.',
      'الشخص ده مش نشط',
      'مينفعش توافق',
      'اختار التواريخ اللي عايز تشوفها',
    ]) {
      expect(colloquial(s), isTrue, reason: s);
    }
    for (final s in [
      'تمت إضافة الموظف. سيسجّل الدخول برمز على واتساب.',
      'هذا الشخص غير نشط',
      'هندسة القائمة',
      'هناك طلب معلّق هنا',
      'اتركهما فارغين',
      'بناءً على الخيار',
    ]) {
      expect(colloquial(s), isFalse, reason: s);
    }
  });

  test('no Egyptian colloquial outside the customer pages: the synced table '
      'and every area supplement', () {
    final files = [
      File('assets/i18n/ar.json'),
      for (final d in Directory('../dashboard_features').listSync())
        if (d is Directory && Directory('${d.path}/assets/i18n').existsSync())
          for (final f in Directory('${d.path}/assets/i18n').listSync())
            if (f is File && f.path.endsWith('ar.json')) f,
    ];
    expect(files.length, greaterThan(10));
    final found = [
      for (final f in files)
        for (final (k, v) in _strings(jsonDecode(f.readAsStringSync())))
          if (!_notDashboard.contains(k.split('.').first) && colloquial(v))
            '${f.path}: $k: $v',
    ];
    expect(found, isEmpty);
  });
}
