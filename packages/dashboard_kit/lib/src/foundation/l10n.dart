import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' hide TextDirection;

part 'l10n_tables.dart';

/// Looks a web i18n key up in the active language, i18next style:
/// `{{name}}` interpolation from [args], plurals through `count`.
typedef DashTranslate =
    String Function(String key, [Map<String, Object?>? args]);

/// Every phrase the kit draws, one field per phrase, each named after the web
/// i18n key it carries (`common.noResults` → [noResults]). The kit never
/// hard-codes a word: it reads these through [DashKitLocalizations].
///
/// dashboard_core builds one from the live i18n with [DashKitStrings.fromLookup];
/// [DashKitStrings.forLanguage] holds the web's own en/ar words for tests and
/// for a kit used before the i18n is up.
@immutable
class DashKitStrings {
  const DashKitStrings._(this._t);

  /// The phrases from a translate function over the web's keys.
  const factory DashKitStrings.fromLookup(DashTranslate t) = DashKitStrings._;

  /// The web's own words (en.json / ar.json) for [languageCode].
  factory DashKitStrings.forLanguage(String languageCode) {
    final table = languageCode == 'ar' ? _arTable : _enTable;
    return DashKitStrings._((key, [args]) {
      final raw = table[key] ?? _enTable[key] ?? key;
      return interpolate(raw, args ?? const {});
    });
  }

  final DashTranslate _t;

  /// i18next `{{name}}` interpolation (no escaping, Latin digits).
  static String interpolate(String raw, Map<String, Object?> args) =>
      raw.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'), (m) {
        final v = args[m.group(1)];
        return v == null ? m.group(0)! : '$v';
      });

  String _(String key, [Map<String, Object?>? args]) =>
      args == null ? _t(key) : _t(key, args);

  // ── common.* ─────────────────────────────────────────────────────────
  String get noResults => _('common.noResults');
  String get loadFailed => _('common.loadFailed');
  String get retry => _('common.retry');
  String get columns => _('common.columns');
  String get actions => _('common.actions');
  String get details => _('common.details');
  String get loadMore => _('common.loadMore');
  String get previous => _('common.previous');
  String get next => _('common.next');
  String page(int current, int total) =>
      _('common.page', {'current': current, 'total': total});
  String get clearAll => _('common.clearAll');
  String get clear => _('common.clear');
  String get back => _('common.back');
  String get close => _('common.close');
  String get cancel => _('common.cancel');
  String get confirm => _('common.confirm');
  String get save => _('common.save');
  String get delete => _('common.delete');
  String get edit => _('common.edit');
  String get add => _('common.add');
  String get search => _('common.search');
  String get searchPlaceholder => _('common.searchPlaceholder');
  String get select => _('common.select');
  String get filters => _('common.filters');
  String get export => _('common.export');
  String get exportExcel => _('common.exportExcel');
  String get exportCsv => _('common.exportCsv');
  String get moreActions => _('common.moreActions');
  String get optional => _('common.optional');
  String get requiredField => _('common.requiredField');
  String get from => _('common.from');
  String get to => _('common.to');
  String get loading => _('common.loading');
  String get none => _('common.none');
  String get all => _('common.all');
  String get on => _('common.on');
  String get off => _('common.off');
  String get selectAllRows => _('common.selectAll');
  String get deselectAll => _('common.deselectAll');
  String get selectTimezone => _('common.selectTimezone');
  String get searchTimezone => _('common.searchTimezone');
  String get listSeparator => _('common.listSeparator');

  // ── datePicker.* ─────────────────────────────────────────────────────
  String get pickDate => _('datePicker.pickDate');
  String get today => _('datePicker.today');
  String get clickDay => _('datePicker.clickDay');
  String get clickStart => _('datePicker.clickStart');
  String get clickEnd => _('datePicker.clickEnd');
  String get rangeSelected => _('datePicker.rangeSelected');
  String get apply => _('datePicker.apply');
  String get custom => _('datePicker.custom');
  String get pastWarning => _('datePicker.pastWarning');

  // ── inputs.* ─────────────────────────────────────────────────────────
  String get needsValue => _('inputs.required');
  String notANumber(String text) => _('inputs.notANumber', {'text': text});
  String between(String min, String max, String unit) =>
      _('inputs.between', {'min': min, 'max': max, 'unit': unit});
  String atLeast(String min, String unit) =>
      _('inputs.atLeast', {'min': min, 'unit': unit});
  String get less => _('inputs.less');
  String get more => _('inputs.more');
  String timeUnreadable(String text) =>
      _('inputs.timeUnreadable', {'text': text});
  String get timePlaceholder => _('inputs.timePlaceholder');
  String get clearTime => _('inputs.clearTime');
  String get times => _('inputs.times');
  String get endsBeforeStart => _('inputs.endsBeforeStart');
  String get quickRanges => _('inputs.quickRanges');
  String get thisPeriod => _('inputs.thisPeriod');
  String get lastPeriod => _('inputs.lastPeriod');
  String get thisMonth => _('inputs.thisMonth');
  String get lastMonth => _('inputs.lastMonth');
  String get thisWeek => _('inputs.thisWeek');
  String get lastWeek => _('inputs.lastWeek');
  String get rangeFrom => _('inputs.from');
  String get rangeTo => _('inputs.to');

  // ── uploader.* ───────────────────────────────────────────────────────
  String get uploadChoose => _('uploader.choose');
  String get uploading => _('uploader.uploading');
  String get uploadReplace => _('uploader.replace');
  String get uploadRemove => _('uploader.remove');
  String get notAnImage => _('uploader.notAnImage');
  String get imageTooLarge => _('uploader.tooLarge');
  String get processing => _('uploader.processing');
  String get processingFailed => _('uploader.processingFailed');

  // ── bilingualField.* ─────────────────────────────────────────────────
  String arabicLabel(String label) =>
      _('bilingualField.arabicLabel', {'label': label});

  // ── grid.* (editable cards, row selection) ───────────────────────────
  String get pasteTitle => _('grid.pasteTitle');
  String get pasteHint => _('grid.pasteHint');
  String pasteColumn(int n) => _('grid.column', {'n': n});
  String get pasteIgnore => _('grid.ignore');
  String pasteSummary(int valid, int total) =>
      _('grid.pasteSummary', {'valid': valid, 'total': total});
  String createN(int count) => _('grid.createN', {'count': count});
  String get pasteRows => _('grid.pasteRows');
  String get selectAll => _('grid.selectAll');
  String get selectRow => _('grid.selectRow');
  String selectedCount(int count) => _('grid.selectedCount', {'count': count});

  // ── menu.* ───────────────────────────────────────────────────────────
  String get costMissingFix => _('menu.costMissingFix');
}

/// How the kit writes figures, money and dates — the web's `lib/format.ts`
/// shapes. dashboard_core may pass its own (the org currency, the branch
/// timezone); [DashKitFormats.new] is the web's default for a language.
@immutable
class DashKitFormats {
  const DashKitFormats({this.languageCode = 'en', this.currency = 'EGP'});

  final String languageCode;

  /// ISO code of the org currency.
  final String currency;

  bool get arabic => languageCode == 'ar';

  static const Map<String, String> _currencyAr = {
    'EGP': 'ج.م',
    'SAR': 'ر.س',
    'AED': 'د.إ',
    'KWD': 'د.ك',
    'QAR': 'ر.ق',
    'BHD': 'د.ب',
    'OMR': 'ر.ع',
    'JOD': 'د.أ',
  };

  /// `EGP` / `ج.م`.
  String get currencyLabel =>
      arabic ? (_currencyAr[currency] ?? currency) : currency;

  static bool _dateData = false;

  /// Date symbols for both languages (bundled with intl; synchronous).
  static void _ensureDates() {
    if (_dateData) return;
    _dateData = true;
    initializeDateFormatting('en_GB');
    initializeDateFormatting('ar');
  }

  /// Western digits and separators, no bidi marks — `numberingSystem: latn`.
  static String _latin(String s) => s
      .replaceAllMapped(
        RegExp('[٠-٩]'),
        (m) => '${m.group(0)!.codeUnitAt(0) - 0x0660}',
      )
      .replaceAll('٫', '.')
      .replaceAll('٬', ',')
      .replaceAll('٪', '%')
      .replaceAll(RegExp('[\u200e\u200f\u061c]'), '');

  /// A grouped figure with Western digits: `12,500.5`.
  String figure(num n, {int minDecimals = 0, int maxDecimals = 2}) {
    final f = NumberFormat.decimalPattern('en_US')
      ..minimumFractionDigits = minDecimals
      ..maximumFractionDigits = maxDecimals;
    return f.format(n);
  }

  String _moneyShape(String figure, String sign) {
    final s = sign == '-' ? MadarFormat.minus : sign;
    return arabic
        ? '${MadarFormat.ltr('$s$figure')} $currencyLabel'
        : '$s$currencyLabel $figure';
  }

  /// Minor units as money: `EGP 1,234.50` / `1,234.50 ج.م` (the figure
  /// LTR-isolated); null is `—`.
  String money(
    int? minor, {
    int? maxFractionDigits,
    bool signed = false,
    bool withCurrency = true,
  }) {
    if (minor == null) return '—';
    final value = minor / 100;
    final max = maxFractionDigits ?? 2;
    final min = max < 2 ? max : 2;
    final fig = figure(value.abs(), minDecimals: min, maxDecimals: max);
    final zero = double.tryParse(fig.replaceAll(',', '')) == 0;
    final sign = zero
        ? ''
        : value < 0
        ? '-'
        : signed
        ? '+'
        : '';
    if (!withCurrency) {
      final s = '${sign == '-' ? MadarFormat.minus : sign}$fig';
      return arabic ? MadarFormat.ltr(s) : s;
    }
    return _moneyShape(fig, sign);
  }

  /// `EGP 1.2K`.
  String moneyCompact(int? minor) {
    if (minor == null) return '—';
    final value = minor / 100;
    final fig = (NumberFormat.compact(
      locale: 'en_US',
    )..maximumFractionDigits = 1).format(value.abs());
    return _moneyShape(fig, value < 0 && fig != '0' ? '-' : '');
  }

  /// A plain number in the language, Western digits, a true minus.
  String number(num n, {int maxDecimals = 3}) {
    final f = NumberFormat.decimalPattern(arabic ? 'ar' : 'en_GB')
      ..maximumFractionDigits = maxDecimals;
    return _latin(f.format(n)).replaceAll('-', MadarFormat.minus);
  }

  /// `2.2K` / `2.2 ألف`.
  String numberCompact(num n) {
    final f = NumberFormat.compact(locale: arabic ? 'ar' : 'en_GB')
      ..maximumFractionDigits = 1;
    return _latin(f.format(n)).replaceAll('-', MadarFormat.minus);
  }

  /// A ratio as a percent, one decimal: `12.3%`.
  String percent(num ratio) {
    final f = NumberFormat.percentPattern(arabic ? 'ar' : 'en_GB')
      ..maximumFractionDigits = 1;
    return _latin(f.format(ratio)).replaceAll('-', MadarFormat.minus);
  }

  /// `07 Oct 2026` / `07 أكتوبر 2026`.
  String date(DateTime? d) {
    if (d == null) return '—';
    _ensureDates();
    return _latin(DateFormat('dd MMM yyyy', arabic ? 'ar' : 'en_GB').format(d));
  }

  /// `October 2026`.
  String monthYear(DateTime d) {
    _ensureDates();
    return _latin(DateFormat('MMMM yyyy', arabic ? 'ar' : 'en_GB').format(d));
  }

  /// Short weekday names, Saturday first (the app's week).
  List<String> weekdaysShort() {
    _ensureDates();
    final f = DateFormat('EEE', arabic ? 'ar' : 'en_GB');
    // 2024-01-06 is a Saturday.
    return [for (var i = 0; i < 7; i++) f.format(DateTime(2024, 1, 6 + i))];
  }

  /// `HH:MM` (24-hour) for reading on the app's 12-hour clock:
  /// `09:30 PM` / `09:30 م`.
  String time(String hhmm, {bool h12 = true}) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
    if (m == null) return '';
    final h = int.parse(m.group(1)!);
    final min = m.group(2)!;
    if (!h12) return '${h.toString().padLeft(2, '0')}:$min';
    final h12v = h % 12 == 0 ? 12 : h % 12;
    final mer = arabic ? (h < 12 ? 'ص' : 'م') : (h < 12 ? 'AM' : 'PM');
    return '${h12v.toString().padLeft(2, '0')}:$min $mer';
  }
}

/// Puts the kit's words and formats above a subtree. The shell installs one
/// under its i18n; tests use [DashKitLocalizations.forLanguage].
class DashKitLocalizations extends InheritedWidget {
  const DashKitLocalizations({
    required this.strings,
    required this.formats,
    required super.child,
    super.key,
  });

  /// The web's own words for [languageCode] (tests, previews).
  DashKitLocalizations.forLanguage(
    String languageCode, {
    required super.child,
    String currency = 'EGP',
    super.key,
  }) : strings = DashKitStrings.forLanguage(languageCode),
       formats = DashKitFormats(languageCode: languageCode, currency: currency);

  final DashKitStrings strings;
  final DashKitFormats formats;

  static DashKitLocalizations? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashKitLocalizations>();

  /// The nearest strings; without an ancestor, the web's words for the
  /// ambient locale.
  static DashKitStrings stringsOf(BuildContext context) =>
      maybeOf(context)?.strings ??
      DashKitStrings.forLanguage(MadarFormat.localeOf(context));

  static DashKitFormats formatsOf(BuildContext context) =>
      maybeOf(context)?.formats ??
      DashKitFormats(languageCode: MadarFormat.localeOf(context));

  @override
  bool updateShouldNotify(DashKitLocalizations oldWidget) =>
      strings != oldWidget.strings || formats != oldWidget.formats;
}

extension DashKitContext on BuildContext {
  /// The kit's words: `context.dashStrings.noResults`.
  DashKitStrings get dashStrings => DashKitLocalizations.stringsOf(this);

  /// The kit's formats: `context.dashFormats.money(1250)`.
  DashKitFormats get dashFormats => DashKitLocalizations.formatsOf(this);

  /// True when the ambient direction is right-to-left.
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}

final RegExp _isolates = RegExp('[\u2066-\u2069]');
final RegExp _arabicScript = RegExp('[؀-ۿ]');

/// A figure ready to drop into either direction of text: a pure figure
/// (`#1042`, `1,284`, `−50.00`) in a left-to-right isolate; a figure that
/// already carries its own isolate or an Arabic word (the Arabic money
/// shape, `1,234.50 ج.م` with the figure isolated) as it is — nesting isolates mis-measures the line, which
/// either wraps the currency or drops it.
String dashFigure(String s) =>
    _isolates.hasMatch(s) || _arabicScript.hasMatch(s) ? s : MadarFormat.ltr(s);
