/// What the web computes in the browser for the Employees unit, as pure
/// functions: the one phone rule (`lib/phone.ts`, `inputs/phone-field.tsx`),
/// how a salary reads to the caller (`dawam/phase-d.ts` `salaryState`), the
/// salary calculator's arithmetic (`dawam/salary-calc.ts`) and the
/// spreadsheet import (`dawam/people.ts`). Money is integer piastres; every
/// figure multiplies before it divides and rounds half away from zero.
library;

import 'package:dashboard_api/dashboard_api.dart' show Employee;
import 'package:rust_bridge_dashboard/rules.dart' as rules;

// ── phones ─────────────────────────────────────────────────────────────

/// Longer than this is refused outright, before any digit is read.
const int phoneRawMax = 32;

String _asciiDigits(String s) => s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
  final c = m.group(0)!.codeUnitAt(0);
  return String.fromCharCode(0x30 + (c >= 0x06f0 ? c - 0x06f0 : c - 0x0660));
});

/// The canonical form of whatever was typed (`201001234567`, E.164 digits
/// without the `+`), or null when it is not a phone: madar-ids
/// `phone::canonical` through the bridge, the copy the backend and the POS
/// core run.
String? canonicalPhone(String? raw) =>
    raw == null ? null : rules.phoneCanonical(raw: raw);

bool isValidPhone(String? raw) => canonicalPhone(raw) != null;

/// Why a typed phone fails (`phoneProblem`): `short`, `long`, `prefix` or
/// `bad`; null when it is fine or empty.
String? phoneProblem(String raw) {
  final text = raw.trim();
  if (text.isEmpty || canonicalPhone(text) != null) return null;
  final digits = _asciiDigits(text).replaceAll(RegExp(r'\D'), '');
  final national = digits.replaceFirst(RegExp('^(00)?20'), '0');
  if (national.startsWith('01')) {
    if (!RegExp('^01[0125]').hasMatch(national)) return 'prefix';
    return national.length < 11 ? 'short' : 'long';
  }
  return 'bad';
}

/// A phone for reading (`formatPhoneDisplay`): `+20 100 123 4567` for an
/// Egyptian mobile, `+<digits>` otherwise; a non-phone as given.
String formatPhoneDisplay(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  final c = canonicalPhone(phone);
  if (c == null) return phone;
  final m = RegExp(r'^20(1\d{2})(\d{3})(\d{4})$').firstMatch(c);
  return m == null ? '+$c' : '+20 ${m[1]} ${m[2]} ${m[3]}';
}

/// The table's WhatsApp cell: `+digits` (the stored number without a doubled
/// plus).
String phoneCell(String phone) => '+${phone.replaceFirst(RegExp(r'^\+'), '')}';

// ── salary ─────────────────────────────────────────────────────────────

enum SalaryState { set, notSet, hidden }

/// How a salary reads to this caller (`salaryState`): `salary_set` false is
/// nobody set one ("Not set"); set with a null figure is hidden from you.
SalaryState salaryStateOf(Employee e) {
  if (!e.salarySet) return SalaryState.notSet;
  return e.baseSalaryPiastres == null ? SalaryState.hidden : SalaryState.set;
}

/// Arabic-Indic digits and separators → a plain number string.
String _normalizeAmount(String text) => _asciiDigits(
  text,
).replaceAll('٫', '.').replaceAll(RegExp('[,٬]'), '').trim();

/// Pounds as typed → piastres; null unless a finite amount above zero
/// (`readPounds`): "٩٬٠٠٠٫٥٠" is 9,000.50.
int? readPounds(String text) {
  final s = _normalizeAmount(text);
  final n = s.isEmpty ? 0.0 : double.tryParse(s);
  if (n == null || !n.isFinite || n <= 0) return null;
  return (n * 100).round();
}

/// Piastres → what an EGP box shows ("250", "31.25"): `String(p / 100)`.
String egpText(int piastres) => jsNumber(piastres / 100);

/// A number as JavaScript's `String(n)` writes it (no ".0" on a whole one).
String jsNumber(num n) {
  if (n is int) return '$n';
  if (n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21) {
    return n.toInt().toString();
  }
  return '$n';
}

/// How a salary divides: working days a month (may be a half) and a working
/// day's minutes.
typedef PayBasis = ({num workingDays, int dayMinutes});

/// 26 working days of 8 hours, unless the rules say otherwise.
const PayBasis defaultPayBasis = (workingDays: 26, dayMinutes: 480);

/// Integer division rounding half away from zero (b > 0).
int roundDiv(int a, int b) {
  final sign = a < 0 ? -1 : 1;
  final abs = a.abs();
  final q = abs ~/ b;
  final r = abs - q * b;
  return sign * (2 * r >= b ? q + 1 : q);
}

typedef Rates = ({int monthly, int daily, int hourly});

/// The three rates from whichever one was typed, in piastres (`rates`).
Rates ratesFrom(PayBasis basis, {int? monthly, int? daily, int? hourly}) {
  final d100 = (basis.workingDays * 100).round();
  final mins = basis.dayMinutes;
  if (monthly != null) {
    return (
      monthly: monthly,
      daily: roundDiv(monthly * 100, d100),
      hourly: roundDiv(monthly * 100 * 60, d100 * mins),
    );
  }
  if (daily != null) {
    return (
      monthly: roundDiv(daily * d100, 100),
      daily: daily,
      hourly: roundDiv(daily * 60, mins),
    );
  }
  final h = hourly!;
  return (
    monthly: roundDiv(h * mins * d100, 6000),
    daily: roundDiv(h * mins, 60),
    hourly: h,
  );
}

DateTime _utc(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

int _dayDiff(String a, String b) => _utc(b).difference(_utc(a)).inDays;

/// The first pay of someone hired on [hireDate]: the monthly salary × days
/// employed ÷ the period's days (`firstPay`). The pay period holding the hire
/// date (periods opening on [startDay], the 26th meaning 26th–25th) is
/// madar-dawam's `pay::period_window` through the core.
({String from, String to, int piastres}) firstPay(
  int monthly,
  String hireDate,
  int startDay,
) {
  final p = rules.payPeriod(day: hireDate, startDay: startDay)!;
  final days = _dayDiff(hireDate, p.to) + 1;
  return (
    from: hireDate,
    to: p.to,
    piastres: roundDiv(monthly * days, _dayDiff(p.from, p.to) + 1),
  );
}

/// `yyyy-mm-dd`, the only hire date the calculator reads.
bool isIsoDate(String? s) =>
    s != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

// ── the spreadsheet import ─────────────────────────────────────────────

/// One person a sheet row describes (`NewPerson`).
class NewPerson {
  const NewPerson({
    required this.row,
    required this.name,
    required this.phone,
    required this.branchId,
    this.salaryPiastres,
  });

  /// The row as numbered in the spreadsheet (the header is 1).
  final int row;
  final String name;

  /// Canonical (`201…`).
  final String phone;
  final String branchId;
  final int? salaryPiastres;
}

/// A row that can't be read, and why (`RowError`): [key] under `dawam.`.
class RowError {
  const RowError(this.row, this.key, [this.value]);
  final int row;
  final String key;
  final String? value;
}

typedef ParsedPeople = ({List<NewPerson> people, List<RowError> errors});

/// Column headers understood, in English and Arabic.
const Map<String, List<String>> importColumns = {
  'name': ['name', 'full name', 'employee', 'الاسم', 'اسم الموظف'],
  'phone': [
    'whatsapp',
    'phone',
    'mobile',
    'whatsapp number',
    'رقم الواتساب',
    'الموبايل',
    'الهاتف',
    'رقم الهاتف',
  ],
  'branch': ['branch', 'الفرع'],
  'salary': ['salary', 'monthly salary', 'الراتب', 'المرتب'],
};

/// A sheet cell as the text it shows (`String(cell ?? "")`, ExcelJS's
/// `cellValue`): a date as `yyyy-mm-dd`, a whole number without ".0".
String cellText(Object? v) => switch (v) {
  null => '',
  final DateTime d => _iso(d.toUtc()),
  final num n => jsNumber(n),
  _ => '$v',
};

String _norm(Object? s) => cellText(s).trim().toLowerCase();

/// Rows as read from a sheet (first row = headers) → people and problems
/// (`parsePeople`).
ParsedPeople parsePeople(
  List<List<Object?>> rows,
  List<({String id, String name})> branches,
) {
  final header = (rows.isEmpty ? const <Object?>[] : rows.first)
      .map(_norm)
      .toList();
  int col(String k) => header.indexWhere(importColumns[k]!.contains);
  final at = {for (final k in importColumns.keys) k: col(k)};
  final byName = {for (final b in branches) _norm(b.name): b.id};
  final only = branches.length == 1 ? branches.first.id : null;
  final people = <NewPerson>[];
  final errors = <RowError>[];
  final seen = <String>{};
  for (var i = 1; i < rows.length; i++) {
    final cells = rows[i];
    final row = i + 1;
    String get(String k) {
      final c = at[k]!;
      return c >= 0 && c < cells.length ? cellText(cells[c]).trim() : '';
    }

    if (cells.every((c) => _norm(c).isEmpty)) continue;
    final name = get('name');
    if (name.isEmpty) {
      errors.add(RowError(row, 'importNoName'));
      continue;
    }
    final phone = canonicalPhone(get('phone'));
    if (phone == null) {
      errors.add(RowError(row, 'importBadPhone', get('phone')));
      continue;
    }
    if (seen.contains(phone)) {
      errors.add(RowError(row, 'importDuplicatePhone', get('phone')));
      continue;
    }
    final branchName = get('branch');
    final branchId = branchName.isNotEmpty ? byName[_norm(branchName)] : only;
    if (branchId == null) {
      errors.add(RowError(row, 'importNoBranch', branchName));
      continue;
    }
    final rawSalary = get('salary').replaceAll(',', '');
    final salary = rawSalary.isEmpty ? null : _jsNumberOf(rawSalary);
    // A salary is more than zero, or left out (the Add dialog's rule).
    if (rawSalary.isNotEmpty &&
        (salary == null || !salary.isFinite || salary <= 0)) {
      errors.add(RowError(row, 'importBadSalary', get('salary')));
      continue;
    }
    seen.add(phone);
    people.add(
      NewPerson(
        row: row,
        name: name,
        phone: phone,
        branchId: branchId,
        salaryPiastres: salary == null ? null : (salary * 100).round(),
      ),
    );
  }
  return (people: people, errors: errors);
}

/// `Number(text)`: blanks around it are fine, anything else not a number is
/// NaN (null here).
double? _jsNumberOf(String text) {
  final s = text.trim();
  if (s.isEmpty) return 0;
  return double.tryParse(s);
}

/// A `.csv` file's text → rows (`readCsv`): quoted fields keep their commas
/// and doubled quotes; CRLF, LF and CR end a row.
List<List<String>> readCsv(String text) {
  final out = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"' && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (ch == '"') {
        quoted = false;
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      out.add(row);
      row = <String>[];
      cell.clear();
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    out.add(row);
  }
  return out;
}

/// Whether [bytes] can be an `.xlsx` (a zip: `PK\x03\x04`). Anything else is
/// refused before it reaches the reader, as ExcelJS refuses it.
bool looksLikeXlsx(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4b &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;
