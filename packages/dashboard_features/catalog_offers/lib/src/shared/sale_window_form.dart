/// A sale window as the combo editor and the deal dialog edit it (the web's
/// `windowSchema`, `emptyWindow`, `windowFromWire`/`windowToWire` and the
/// window rules of `comboSchema`): text in, the wire's `SaleWindow` out.
library;

import 'package:dashboard_api/dashboard_api.dart' show SaleWindow;
import 'package:flutter/foundation.dart';

import 'offers_format.dart';

var _seq = 0;

/// A client key for a new row (never sent).
String newOffersKey(String prefix) => '$prefix-${_seq++}';

/// One window in a form. Empty strings mean "none": [branchId] '' = every
/// branch, [startsAt]/[endsAt] '' = the whole day, [validFrom]/[validTo]
/// '' = no date bound. Times are `HH:MM`, dates `YYYY-MM-DD`.
@immutable
class WindowDraft {
  const WindowDraft({
    required this.key,
    this.branchId = '',
    this.weekdays = allWeekdays,
    this.startsAt = '',
    this.endsAt = '',
    this.validFrom = '',
    this.validTo = '',
  });

  /// A new window: every day, no hours, no dates, all branches.
  factory WindowDraft.empty() => WindowDraft(key: newOffersKey('w'));

  factory WindowDraft.fromWire(SaleWindow w) => WindowDraft(
    key: newOffersKey('w'),
    branchId: w.branchId ?? '',
    weekdays: w.weekdays ?? allWeekdays,
    startsAt: hhmm(w.startsAt) ?? '',
    endsAt: hhmm(w.endsAt) ?? '',
    validFrom: w.validFrom ?? '',
    validTo: w.validTo ?? '',
  );

  final String key;
  final String branchId;
  final int weekdays;
  final String startsAt;
  final String endsAt;
  final String validFrom;
  final String validTo;

  WindowDraft copyWith({
    String? branchId,
    int? weekdays,
    String? startsAt,
    String? endsAt,
    String? validFrom,
    String? validTo,
  }) => WindowDraft(
    key: key,
    branchId: branchId ?? this.branchId,
    weekdays: weekdays ?? this.weekdays,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    validFrom: validFrom ?? this.validFrom,
    validTo: validTo ?? this.validTo,
  );

  /// The wire window: hours only when both are set, "none" as an explicit
  /// null (the web sends every field).
  SaleWindow toWire() {
    final s = hhmm(startsAt);
    final e = hhmm(endsAt);
    final hours = s != null && e != null;
    return SaleWindow(
      branchId: branchId.isEmpty ? null : branchId,
      weekdays: weekdays,
      startsAt: hours ? s : null,
      endsAt: hours ? e : null,
      validFrom: validFrom.isEmpty ? null : validFrom,
      validTo: validTo.isEmpty ? null : validTo,
      explicitNulls: const {
        'branch_id',
        'starts_at',
        'ends_at',
        'valid_from',
        'valid_to',
      },
    );
  }

  /// Same values (the key aside): for "unsaved changes".
  bool sameAs(WindowDraft o) =>
      branchId == o.branchId &&
      weekdays == o.weekdays &&
      startsAt == o.startsAt &&
      endsAt == o.endsAt &&
      validFrom == o.validFrom &&
      validTo == o.validTo;
}

/// A window's errors, as i18n keys (`combos.errors.*`), by the field they
/// show under.
@immutable
class WindowErrors {
  const WindowErrors({this.weekdays, this.endsAt, this.validTo});

  /// "Pick at least one day."
  final String? weekdays;

  /// "Set both times, or neither." / "The start and end times can't be the
  /// same."
  final String? endsAt;

  /// "The last day can't be before the first."
  final String? validTo;

  bool get isEmpty => weekdays == null && endsAt == null && validTo == null;
}

/// The window rules of the web's schema.
WindowErrors validateWindow(WindowDraft w) {
  final s = hhmm(w.startsAt);
  final e = hhmm(w.endsAt);
  return WindowErrors(
    weekdays: w.weekdays & allWeekdays == 0 ? 'combos.errors.noDays' : null,
    endsAt: (s == null) != (e == null)
        ? 'combos.errors.hoursPair'
        : (s != null && s == e ? 'combos.errors.hoursSame' : null),
    validTo:
        w.validFrom.isNotEmpty &&
            w.validTo.isNotEmpty &&
            w.validFrom.compareTo(w.validTo) > 0
        ? 'combos.errors.datesOrder'
        : null,
  );
}
