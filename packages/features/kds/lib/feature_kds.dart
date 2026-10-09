/// Madar POS — the kitchen board: outstanding tickets by station in an
/// adaptive grid, age-tinted headers, tap-to-bump / recall lines, Bump all,
/// and an honest picture of the kitchen's outbox (queued taps, refused
/// taps). Backed by the exported per-station `kdsProvider` family, which
/// the core keeps truthful and `kdsRevisionProvider` keeps in step across
/// screens.
///
/// Mounted by Queue's Kitchen segment, behind the routing-mode gate, with a
/// null station: the till's own kitchen tab for one-device shops (spec PS-3).
/// Kitchen screens on their own device are the Madar Kitchen app
/// (`apps/kitchen`).
library;

export 'src/kds_board_body.dart' show KdsBoardBody;
export 'src/kds_provider.dart'
    show
        KdsNotifier,
        KdsState,
        kKitchenOpTypes,
        kdsProvider,
        kdsRevisionProvider;
export 'src/kds_ticket_card.dart'
    show KdsTicketCard, kdsAgeDangerMinutes, kdsAgeTone, kdsAgeWarnMinutes;
