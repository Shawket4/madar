/// Madar POS — the Queue: the teller's one inbox over the shared Rust core.
///
/// `QueueScreen` carries two segments — **Bills** (open tickets waiting to be
/// charged, kitchen-ready first) and **Online** (the branch's live delivery
/// and pickup orders: accept with a ready-in time in one act, decline with a
/// reason, step the lifecycle, charge). Both are fed by the shell's realtime
/// ticks and both charge through the ONE shared checkout drawer. The Kitchen
/// segment (routing mode `till`) waits on a flag the bridge cannot read.
///
/// `IncomingScreen` is the app's existing entry name and still works.
library;

export 'src/bills_segment.dart' show BillsSegment, OpenBill;
export 'src/details_sheets.dart' show DeliveryDetailsSheet, TicketDetailsSheet;
export 'src/incoming_provider.dart'
    show
        IncomingNotifier,
        IncomingState,
        QueueSegment,
        incomingProvider,
        kActiveDeliveryStatuses,
        kPrepOffsets;
export 'src/incoming_screen.dart' show IncomingScreen;
export 'src/online_segment.dart' show AcceptingRow, OnlineSegment;
export 'src/queue_screen.dart' show QueueScreen;
export 'src/queue_strings.dart' show QueueKeys, QueueTr;
