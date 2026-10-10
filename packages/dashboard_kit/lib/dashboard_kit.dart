/// The dashboard UI kit on design_system — the Flutter port of the web
/// dashboard's shared components (`src/components/app/**`, `ui/**`).
///
/// Every widget reads right-to-left, both themes and phone / tablet /
/// desktop widths, and draws no word of its own: phrases come through
/// [DashKitLocalizations] (filled by dashboard_core from the web's i18n
/// keys) or as parameters.
library;

export 'src/buttons.dart';
export 'src/charts.dart';
export 'src/controls.dart';
export 'src/dates.dart';
export 'src/display.dart';
export 'src/editable_cards.dart';
export 'src/fields.dart';
export 'src/filters.dart';
export 'src/foundation/l10n.dart';
export 'src/foundation/popover.dart';
export 'src/foundation/press.dart';
export 'src/foundation/tokens.dart';
export 'src/misc.dart';
export 'src/overlays.dart';
export 'src/page.dart';
export 'src/select.dart';
export 'src/stats.dart';
export 'src/table.dart';
export 'src/time.dart';
export 'src/toast.dart';
export 'src/uploader.dart';
