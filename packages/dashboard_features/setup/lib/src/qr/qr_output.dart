/// How every code on Settings › Links & QR codes comes out
/// (`features/qr/output.ts`): the shop's choice of card or plain code, its
/// resolution, and whether it carries any branding.
///
/// Remembered per shop on this device (`madar.qr.output.<orgId>`, the
/// device's preferences, the web's localStorage), the way the Items Sold
/// exclusions are: it is how this person likes their codes printed, not a
/// rule the business sets, so it needs no server field.
///
/// The four settings, and what each one sends:
/// - `unbranded`: the code and nothing else, a square QR, black on a white
///   quiet zone. No card, no frame, no caption, no "Powered by", no Madar
///   mark, no shop name. It overrides `card`.
/// - `centreLogo`: only with `unbranded`: the shop's own logo in the middle.
///   Off, a completely plain QR.
/// - `card`: branded mode only: the A6 card, or the small receipt code.
/// - `dpi`: the raster's resolution, for the card and the unbranded code.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The resolutions offered (`QR_DPIS`).
const List<int> qrDpis = [150, 300, 600];

/// One shop's choice ([qrOutputProvider]).
class QrOutput {
  const QrOutput({
    this.unbranded = false,
    this.centreLogo = true,
    this.card = true,
    this.dpi = 600,
  });

  /// [json] read defensively: anything malformed falls back field by field.
  factory QrOutput.fromJson(Object? json) {
    if (json is! Map) return const QrOutput();
    bool flag(Object? v, bool d) => v is bool ? v : d;
    const d = QrOutput();
    final dpi = json['dpi'];
    return QrOutput(
      unbranded: flag(json['unbranded'], d.unbranded),
      centreLogo: flag(json['centreLogo'], d.centreLogo),
      card: flag(json['card'], d.card),
      dpi: dpi is int && qrDpis.contains(dpi) ? dpi : d.dpi,
    );
  }

  final bool unbranded;
  final bool centreLogo;
  final bool card;
  final int dpi;

  QrOutput copyWith({
    bool? unbranded,
    bool? centreLogo,
    bool? card,
    int? dpi,
  }) => QrOutput(
    unbranded: unbranded ?? this.unbranded,
    centreLogo: centreLogo ?? this.centreLogo,
    card: card ?? this.card,
    dpi: dpi ?? this.dpi,
  );

  Map<String, Object?> toJson() => {
    'unbranded': unbranded,
    'centreLogo': centreLogo,
    'card': card,
    'dpi': dpi,
  };

  @override
  bool operator ==(Object other) =>
      other is QrOutput &&
      other.unbranded == unbranded &&
      other.centreLogo == centreLogo &&
      other.card == card &&
      other.dpi == dpi;

  @override
  int get hashCode => Object.hash(unbranded, centreLogo, card, dpi);

  @override
  String toString() => 'QrOutput(${toJson()})';
}

/// The device setting's key.
String qrOutputPrefKey(String orgId) => 'madar.qr.output.$orgId';

/// The output for [orgId], read from the device and written back on every
/// change. One value per shop, shared by every control and every code: the
/// panel above the codes and the switches in a code's preview are the same
/// switch. Without an org nothing is saved and the default applies.
class QrOutputNotifier extends Notifier<QrOutput> {
  QrOutputNotifier(this.orgId);

  final String? orgId;

  @override
  QrOutput build() {
    final org = orgId;
    if (org == null) return const QrOutput();
    return QrOutput.fromJson(
      ref.read(preferencesProvider).getJson(qrOutputPrefKey(org)),
    );
  }

  void update(QrOutput next) {
    final org = orgId;
    if (org == null) return;
    state = next;
    ref.read(preferencesProvider).setJson(qrOutputPrefKey(org), next.toJson());
  }
}

final qrOutputProvider = NotifierProvider.autoDispose
    .family<QrOutputNotifier, QrOutput, String?>(QrOutputNotifier.new);

/// The render query every QR endpoint takes (`QrRenderQuery` on the server).
typedef QrRenderParams = ({
  bool? card,
  int? dpi,
  bool? unbranded,
  bool? centreLogo,
});

/// The query for [o] (`qrRenderParams`). Unbranded sends only what the plain
/// code reads; branded mode sends exactly what the page always sent, so a
/// shop that never turns it on prints the same card it always has.
QrRenderParams qrRenderParams(QrOutput o) => o.unbranded
    ? (card: null, dpi: o.dpi, unbranded: true, centreLogo: o.centreLogo)
    : (card: o.card, dpi: o.dpi, unbranded: null, centreLogo: null);

/// [p] at another resolution (the output panel's small sample).
QrRenderParams qrAtDpi(QrRenderParams p, int dpi) =>
    (card: p.card, dpi: dpi, unbranded: p.unbranded, centreLogo: p.centreLogo);

/// What a code's image is, for printing it at its real size.
enum QrShape { plain, card, receipt }

QrShape qrShape(QrOutput o) => o.unbranded
    ? QrShape.plain
    : o.card
    ? QrShape.card
    : QrShape.receipt;
