/// What the Combos and deals settings pane reads and works out in the
/// browser (`features/combos/combo-settings-page.tsx`, `util.ts`
/// `percentToRate` / `rateToPercent` / `invalidateCombos`).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ChannelOverride, ChannelToggles, ComboSettings, ComboSettingsWrite;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class ComboSettingsPaths {
  static const String settings = '/settings/combos';

  /// `invalidateCombos`: every list, editor and report that reads combos,
  /// deals or these settings.
  static const List<String> invalidated = [
    '/combos',
    '/deals',
    '/settings/combos',
    '/reports/bundles',
    '/menu-items',
    '/costing',
  ];
}

/// `GET /settings/combos` (`useComboSettings`). The request names no org
/// (the server takes the caller's); the key is the scoped org so a platform
/// admin who switches org never sees the previous org's answer.
final comboSettingsProvider = FutureProvider.autoDispose
    .family<ComboSettings, String?>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(ComboSettingsPaths.settings));
      return ref.watch(apiProvider).menu.getSettings();
    });

/// `COMBO_CHANNELS`, in the web's order.
enum ComboChannel {
  pos('combos.channels.pos', 'combos.channels.posHint', 'store'),
  qr('combos.channels.qr', 'combos.channels.qrHint', 'qr-code'),
  online('combos.channels.online', 'combos.channels.onlineHint', 'globe'),
  delivery('combos.channels.delivery', 'combos.channels.deliveryHint', 'truck');

  const ComboChannel(this.labelKey, this.hintKey, this.icon);

  final String labelKey;
  final String hintKey;
  final String icon;
}

/// A branch cell: follow the org, or on / off here (`Tri`).
enum ComboTri { inherit, on, off }

ComboTri triOf(bool? v) => switch (v) {
  true => ComboTri.on,
  false => ComboTri.off,
  null => ComboTri.inherit,
};

bool? boolOf(ComboTri v) => switch (v) {
  ComboTri.on => true,
  ComboTri.off => false,
  ComboTri.inherit => null,
};

bool? overrideValue(ChannelOverride o, ComboChannel c) => switch (c) {
  ComboChannel.pos => o.pos,
  ComboChannel.qr => o.qr,
  ComboChannel.online => o.online,
  ComboChannel.delivery => o.delivery,
};

/// `{...overrideOf(branch), [channel]: v}`; null = follow.
ChannelOverride overrideWith(ChannelOverride o, ComboChannel c, bool? v) =>
    ChannelOverride(
      pos: c == ComboChannel.pos ? v : o.pos,
      qr: c == ComboChannel.qr ? v : o.qr,
      online: c == ComboChannel.online ? v : o.online,
      delivery: c == ComboChannel.delivery ? v : o.delivery,
      explicitNulls: {
        for (final ch in ComboChannel.values)
          if ((ch == c ? v : overrideValue(o, ch)) == null) ch.name,
      },
    );

/// Whether [o] still sets any channel (else the override is deleted).
bool overrideSetsAny(ChannelOverride o) =>
    ComboChannel.values.any((c) => overrideValue(o, c) != null);

/// The branch's saved override (`overrideOf`), or nothing set.
ChannelOverride overrideOf(ComboSettings s, String branchId) {
  for (final o in s.branchOverrides) {
    if (o.branchId == branchId) return o.sell;
  }
  return const ChannelOverride();
}

/// `channelsOf`: a channel the server leaves out is on.
Map<ComboChannel, bool> channelsOf(ChannelToggles c) => {
  ComboChannel.pos: c.pos ?? true,
  ComboChannel.qr: c.qr ?? true,
  ComboChannel.online: c.online ?? true,
  ComboChannel.delivery: c.delivery ?? true,
};

/// A wire rate ("0.5933") as a number, or null (`rateOf`).
double? rateOf(String? v) {
  if (v == null || v.isEmpty) return null;
  final n = double.tryParse(v);
  return n != null && n.isFinite ? n : null;
}

/// JS `String(n)`: no trailing ".0" on a whole number.
String _jsNumber(double n) =>
    n == n.truncateToDouble() ? n.toInt().toString() : n.toString();

/// The wire's string decimal → the form's percent ("0.55" → "55"); null → "".
String rateToPercent(String? rate) {
  final r = rateOf(rate);
  if (r == null) return '';
  return _jsNumber((r * 10000).round() / 100);
}

/// The form's percent ("55") → the wire's decimal ("0.5500"); blank → null.
String? percentToRate(String pct) {
  if (pct.trim().isEmpty) return null;
  final n = double.tryParse(pct.trim());
  if (n == null || !n.isFinite) return null;
  return ((n * 100).round() / 10000).toStringAsFixed(4);
}

/// `settingsSchema.min_margin`: blank, or a number with 0 ≤ n < 100.
bool marginOk(String v) {
  if (v.trim().isEmpty) return true;
  final n = double.tryParse(v.trim());
  return n != null && n.isFinite && n >= 0 && n < 100;
}

/// The org form's values (`SettingsValues`); equality is the web's `isDirty`.
@immutable
class ComboSettingsForm {
  const ComboSettingsForm({required this.minMargin, required this.sell});

  factory ComboSettingsForm.from(ComboSettings s) => ComboSettingsForm(
    minMargin: rateToPercent(s.minMargin),
    sell: channelsOf(s.channels),
  );

  final String minMargin;
  final Map<ComboChannel, bool> sell;

  ComboSettingsForm withMargin(String v) =>
      ComboSettingsForm(minMargin: v, sell: sell);

  ComboSettingsForm withChannel(ComboChannel c, bool v) =>
      ComboSettingsForm(minMargin: minMargin, sell: {...sell, c: v});

  /// The PUT body: the rate (an explicit null when blank) and all four
  /// switches.
  ComboSettingsWrite toWire() {
    final rate = percentToRate(minMargin);
    return ComboSettingsWrite(
      minMargin: rate,
      channels: ChannelToggles(
        pos: sell[ComboChannel.pos],
        qr: sell[ComboChannel.qr],
        online: sell[ComboChannel.online],
        delivery: sell[ComboChannel.delivery],
      ),
      explicitNulls: rate == null ? const {'min_margin'} : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ComboSettingsForm &&
      other.minMargin == minMargin &&
      mapEquals(other.sell, sell);

  @override
  int get hashCode => Object.hash(
    minMargin,
    Object.hashAll([for (final c in ComboChannel.values) sell[c]]),
  );
}
