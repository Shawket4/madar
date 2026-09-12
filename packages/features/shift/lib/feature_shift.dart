/// Madar POS — the Till: open/close shift, cash in / out, this shift's
/// figures, every drawer for a manager, the Z-report preview, past shifts.
///
/// The shell mounts `TillScreen` as the teller's fourth tab; the other
/// screens are pushed from it (and `OpenShiftScreen` is its no-shift home).
library;

export 'src/cash_in_out_panel.dart';
export 'src/cash_movements_screen.dart';
export 'src/close_shift_screen.dart';
export 'src/drawers_card.dart';
export 'src/open_shift_screen.dart';
export 'src/shift_history_screen.dart';
export 'src/shift_providers.dart';
export 'src/shift_report_sheet.dart';
export 'src/till_screen.dart';
