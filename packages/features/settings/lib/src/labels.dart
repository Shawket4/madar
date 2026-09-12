/// Small label helpers shared by Settings and Me: the role word, and the
/// one-line printer summary a row shows before you open the sheet. Both
/// read the core's i18n; nothing here is a user-visible literal.
library;

import 'package:rust_bridge/rust_bridge.dart';

/// Raster widths the core prints at: 58 mm portables (the Bluetooth
/// default) and 80 mm desktop rolls.
const int paperDots58 = 384;
const int paperDots80 = 576;

/// The wire role (`super_admin` | `org_admin` | `branch_manager` | `teller`
/// | `waiter` | `kitchen`) as a word. An unknown role shows humanised, not
/// raw.
String roleLabel(MadarBridge bridge, String role) {
  final key = switch (role) {
    'waiter' => 'role.waiter',
    'teller' => 'role.teller',
    'branch_manager' => 'role.branch_manager',
    'org_admin' => 'role.org_admin',
    'super_admin' => 'role.super_admin',
    'kitchen' => 'role.kitchen',
    _ => null,
  };
  if (key == null) return role.replaceAll('_', ' ');
  return bridge.tr(key: key);
}

/// Effective paper width in dots — the core's own default (Bluetooth →
/// 58 mm, LAN → 80 mm) until the user pins one.
int effectivePaperDots(DeviceConfigView config) {
  final bluetooth = (config.printerTransport ?? 'lan') == 'bluetooth';
  return config.printerPaperDots ?? (bluetooth ? paperDots58 : paperDots80);
}

/// True when a printer is actually reachable by configuration: a LAN host
/// or a bound Bluetooth device. The Done card's "Not printed — no printer"
/// and the Printer row's summary agree on this.
bool printerBound(DeviceConfigView config) {
  final bluetooth = (config.printerTransport ?? 'lan') == 'bluetooth';
  if (bluetooth) return config.printerBtAddress != null;
  return (config.printerHost?.trim() ?? '').isNotEmpty;
}

/// "Epson · LAN · 80 mm" / "Star · Bluetooth · 58 mm" / "No printer".
String printerSummary(MadarBridge bridge, DeviceConfigView config) {
  if (!printerBound(config)) return bridge.tr(key: 'settings.printer_none');
  final bluetooth = (config.printerTransport ?? 'lan') == 'bluetooth';
  final brand = bridge.tr(
    key: config.printerBrand == 'star'
        ? 'settings.printer_star'
        : 'settings.printer_epson',
  );
  final transport = bridge.tr(
    key: bluetooth ? 'settings.printer_bluetooth' : 'settings.printer_lan',
  );
  final paper = bridge.tr(
    key: effectivePaperDots(config) == paperDots58
        ? 'settings.printer_paper_58'
        : 'settings.printer_paper_80',
  );
  return '$brand · $transport · $paper';
}
