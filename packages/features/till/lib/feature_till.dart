/// Madar POS — the Till: open/close till, cash in / out, this till's
/// figures, every drawer for a manager, the Z-report preview, past tills.
///
/// The shell mounts `TillScreen` as the teller's fourth tab; the other
/// screens are pushed from it (and `OpenTillScreen` is its no-till home).
library;

export 'src/cash_in_out_panel.dart';
export 'src/cash_movements_screen.dart';
export 'src/cash_spot_screen.dart';
export 'src/close_till_screen.dart';
export 'src/drawers_card.dart';
export 'src/open_till_screen.dart';
export 'src/till_history_screen.dart';
export 'src/till_notices.dart';
export 'src/till_providers.dart';
export 'src/till_report_sheet.dart';
export 'src/till_screen.dart';
export 'src/till_sync_strip.dart';
