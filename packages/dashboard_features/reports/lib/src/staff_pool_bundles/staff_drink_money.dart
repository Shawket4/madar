/// Reading a staff drink's money off the wire (`features/staff-pool/util.ts`).
///
/// Three kinds of row reach the report, and they are never folded together:
///
/// - **unpriced**: rung by a till from before priced staff drinks; there is
///   no sale line behind it, so `comp_minor` is null. That is "unknown", not
///   "nothing was given": it shows as a dash, never as 0;
/// - **priced**: the server priced the comp; any figure the till sent agreed,
///   or none was sent;
/// - **priced, and the till disagreed**: an offline till claimed one comp and
///   the server's recount says another; the row carries both.
library;

import 'package:dashboard_api/dashboard_api.dart' show StaffDrink;

/// What a drink gave away and still charged (`StaffDrinkMoney`).
sealed class StaffDrinkMoney {
  const StaffDrinkMoney();
}

/// No figures: rung before staff drinks were priced.
final class StaffDrinkUnpriced extends StaffDrinkMoney {
  const StaffDrinkUnpriced();
}

final class StaffDrinkPriced extends StaffDrinkMoney {
  const StaffDrinkPriced({
    required this.comp,
    required this.extras,
    required this.tillSaid,
  });

  /// What the pool gave free, as the server prices it.
  final int comp;

  /// What the line was still charged; null when the server did not say.
  final int? extras;

  /// The till's claim, only when it differs from the server's.
  final int? tillSaid;
}

/// `staffDrinkMoney(d)`.
StaffDrinkMoney staffDrinkMoney(StaffDrink d) {
  final comp = d.compMinor;
  if (comp == null) return const StaffDrinkUnpriced();
  final reported = d.compMinorReported;
  return StaffDrinkPriced(
    comp: comp,
    extras: d.extrasMinor,
    tillSaid: reported != null && reported != comp ? reported : null,
  );
}
