/// Madar POS — the kitchen board: outstanding tickets by station in an
/// adaptive grid, age-tinted headers, tap-to-bump / recall lines, Bump all,
/// and an honest picture of the kitchen's outbox (queued taps, refused
/// taps). Backed by the exported per-station `kdsProvider` family, which
/// the core keeps truthful and `kdsRevisionProvider` keeps in step across
/// screens.
///
/// Two mount points share it: the kitchen device's `KitchenDisplayScreen`
/// and — behind the routing-mode gate — Queue's Kitchen segment, which
/// mounts `KdsBoardBody` with a null station.
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
export 'src/kitchen_display_screen.dart' show KitchenDisplayScreen;
