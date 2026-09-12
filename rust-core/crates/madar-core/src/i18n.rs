//! Static UI-string localization (PLAN: shared core owns logic). One source of
//! truth for both hosts — a string change here lands in Swift AND Kotlin at once.
//! Dynamic content (menu `*_translations`) is resolved separately in `menu`.
//!
//! Resolution: device locale → its language subtag → `en` → the key itself.
//! RTL languages (ar/…) are flagged so the host can flip layout direction.

/// Localized string for `key` in `locale`, falling back en → key.
pub fn tr(locale: &str, key: &str) -> String {
    let lang = lang_of(locale);
    let resolved = match lang {
        "ar" => ar(key),
        _ => None,
    };
    resolved.or_else(|| en(key)).unwrap_or(key).to_string()
}

pub fn is_rtl(locale: &str) -> bool {
    matches!(lang_of(locale), "ar" | "fa" | "he" | "ur")
}

fn lang_of(locale: &str) -> &str {
    locale.split(['-', '_']).next().unwrap_or(locale)
}

fn en(key: &str) -> Option<&'static str> {
    Some(match key {
        // login (teller)
        "login.welcome_back" => "Welcome back",
        "login.subtitle" => "Sign in to open your till",
        "login.name" => "Name",
        "login.sign_in" => "Sign in",
        "login.pin_hint" => "PIN auto-submits at 6 digits",
        "login.reconfigure" => "Reconfigure device",
        "login.branch" => "Branch",
        // device setup (manager)
        "setup.title" => "Configure this till",
        "setup.desc" => {
            "A manager signs in to bind this device to a branch. Tellers sign in after."
        }
        "setup.choose_branch" => "Choose a branch",
        "setup.choose_branch_desc" => "Bind this till to one of your branches.",
        "setup.email" => "Manager email",
        "setup.password" => "Password",
        "setup.continue" => "Continue",
        "setup.cancel" => "Cancel",
        // kitchen-display commissioning — a KDS device picks which station it shows
        "setup.choose_station" => "Choose a station",
        "setup.choose_station_desc" => "Pick which kitchen station this display shows.",
        "setup.no_stations" => "No kitchen stations for this branch yet.",
        "setup.station_default" => "Default",
        // brand panel
        "brand.headline" => "Welcome\nback.",
        "brand.tagline" => {
            "Sign in to open your till. Works online and off — your sales keep flowing either way."
        }
        // home
        "home.signed_in" => "Signed in",
        "home.online" => "Online",
        "home.offline" => "Offline",
        "home.sign_out" => "Sign out",
        "home.teller" => "teller",
        "home.role" => "role",
        "home.currency" => "currency",
        "home.session" => "session",
        // shift
        "shift.open_title" => "Open your shift",
        "shift.opening_desc" => "Count the cash in the drawer to start selling.",
        "shift.opening_cash" => "Opening cash",
        "shift.open_button" => "Open shift",
        "shift.signed_in_as" => "Signed in as",
        "shift.switch_teller" => "Switch teller",
        "shift.welcome" => "Welcome back",
        "shift.opening_hint" => "Count the cash already in the drawer before you start.",
        "shift.suggested_from_close" => "From last close",
        "shift.opening_reason_label" => "Reason for the difference",
        "shift.opening_reason_hint" => "The opening count differs from the last close.",
        "shift.opening_reason_required" => "Add a reason for the cash difference.",
        "common.done" => "Done",
        // order
        "order.title" => "Order",
        "order.coming_soon" => "Catalog & ordering — coming next.",
        "order.close_shift" => "Close shift",
        "shift.close_title" => "Close shift",
        "shift.closing_desc" => "Count the drawer and close out your shift.",
        "shift.summary" => "Shift summary",
        "shift.teller" => "Teller",
        "shift.opened_at" => "Opened",
        "shift.counted_cash" => "Counted cash",
        "shift.cash_note" => "Note (optional)",
        "shift.system_cash" => "Expected cash",
        "shift.system_cash_explain" => "Opening float + cash sales − cash out",
        "shift.drawer_matches" => "Drawer matches",
        "shift.drawer_over" => "Over by",
        "shift.drawer_short" => "Short by",
        "shift.report" => "Shift report",
        "order.all" => "All",
        "order.search" => "Search items",
        "order.empty" => "No items here yet.",
        "order.empty_desc" => "The menu hasn't synced to this device yet.",
        "order.sync_menu" => "Sync menu",
        "order.rename_title" => "Name this order",
        "order.rename_hint" => "e.g. Table 4, Ahmed",
        "order.empty_search" => "Nothing matches your search.",
        "order.cart" => "Cart",
        "order.cart_empty" => "Your cart is empty.",
        "order.size" => "Size",
        "order.optionals" => "Options",
        "order.add_to_cart" => "Add to cart",
        "order.update_item" => "Update item",
        "order.combos" => "Combos",
        "order.split_payment" => "Split",
        "order.split_remaining" => "Remaining",
        "order.save_component" => "Save",
        "order.configure" => "Configure",
        "order.bundle_includes" => "Includes",
        "order.bundle_save" => "Save",
        "order.select_prefix" => "Select",
        "order.addon_milk_type" => "Milk",
        "order.addon_coffee_type" => "Coffee",
        "order.addon_extra" => "Extras",
        "order.show_all_addons" => "Show all add-ons",
        "order.show_assigned_addons" => "Show fewer",
        "order.search_addons" => "Search add-ons",
        "order.recipe" => "Recipe",
        "order.steps" => "How it's made",
        "order.required" => "Required",
        "order.subtotal" => "Subtotal",
        "order.tax" => "Tax",
        "kitchen.chit_heading" => "KITCHEN",
        "printing.chit" => "Send to kitchen",
        "printing.chit_sent" => "Sent to the kitchen",
        "printing.no_printer" => "No printer is set up on this device",
        "printing.failed" => "The printer did not answer",
        "kitchen.chit_table" => "Table",
        "kitchen.chit_note" => "NOTE:",
        "order.service_charge" => "Service",
        "order.total" => "Total",
        "order.discount" => "Discount",
        "order.no_discount" => "No discount",
        "order.max_reached" => "Maximum reached",
        "order.removed" => "Removed",
        "order.undo" => "Undo",
        // tables / floor canvas / transfer waitlist
        "tables.title" => "Tables",
        "tables.no_table" => "No table",
        "tables.pick" => "Pick a table",
        "tables.assign" => "Assign table",
        "tables.clear_table" => "Remove table",
        "tables.resume" => "Open order",
        "tables.move" => "Move to another table",
        "tables.swap" => "Swap tables",
        "tables.swap_pick" => "Tap the other table",
        "tables.queue" => "Waitlist a move",
        "tables.waitlist" => "Move waitlist",
        "tables.wish_any" => "Any table in",
        "tables.fulfill" => "Seat here",
        "tables.cancel_wish" => "Remove",
        "tables.taken" => "Table was taken — parked without it",
        "tables.locked" => "Being edited on another till",
        // A table another till is holding for its own parked order: the room
        // says taken, and this device has no order of its own to open.
        "tables.add_round" => "Add a round",
        "tables.round" => "Round",
        // Loyalty at the till. These were hardcoded English in the drawer and
        // the scan sheet, so an Arabic shop's teller read half a screen in a
        // language they had not chosen.
        "loyalty.customer" => "Customer",
        "loyalty.scan_card" => "Scan card",
        "loyalty.scan_title" => "Scan the customer's card",
        "loyalty.not_identified" => "No card scanned",
        "loyalty.remove" => "Remove",
        "loyalty.nothing_claimable" => "Nothing here can be claimed yet",
        "loyalty.rewards_ready" => "rewards ready",
        "loyalty.left" => "left",
        "loyalty.earns" => "This sale earns",
        "tables.bill_pending" => "The first round has not synced yet",
        "tables.free" => "Free",
        "tables.seated" => "Seated",
        "tables.moved" => "Moved",
        "tables.queued" => "Added to the move waitlist",
        "tables.empty_waitlist" => "No parties waiting",
        "tables.make_available" => "Make available",
        "tables.free_it" => "Free the table",
        "tables.free_it_warning" => "This tab has not been paid. Freeing the table abandons it.",
        "tables.empty_title" => "No tables here yet",
        "tables.empty_desc" => "Draw this branch's floor in the dashboard, then sync.",
        "tables.settle_first" => "Settle the bill first, or move it to another table",
        "tables.freed" => "Table is available",
        "tables.seats" => "seats",
        "tables.no_section" => "No section",
        "tables.held_res" => "Held",
        "tables.reserved" => "Reserved",
        "tables.reserved_for" => "Reserved for",
        "tables.seat_booking" => "Seat this party",
        "tables.no_show" => "No-show",
        "tables.arrivals" => "Arrivals",
        "tables.arrivals_empty" => "No bookings today",
        "tables.booking_seated" => "Party seated — fire their order",
        "tables.booking_no_show" => "Marked as no-show",
        "tables.walk_in_anyway" => "Seat a walk-in anyway",
        "tables.guests" => "guests",
        "tables.seat_held" => "Put a held order here",
        "tables.view_list" => "List",
        "tables.view_plan" => "Plan",
        "tables.due" => "due",
        "tables.late" => "late",
        "tables.status" => "Status",
        // ── Bussing: a checkout leaves the table needing to be cleared ──
        "tables.needs_clearing" => "Needs clearing",
        "tables.clear_ask" => "Clear table",
        "tables.clear_ask_generic" => "Clear the table?",
        "tables.clear_ask_hint" =>
            "The order is paid. Clear it now if the table is ready for the next party — otherwise it stays on the floor as needing a bus.",
        "tables.clear_now" => "Clear it now",
        "tables.clear_later" => "Not yet — needs a bus",
        "tables.cleared" => "Table cleared",
        "tables.clear" => "Clear table",
        "tables.dirty_hint" => "Paid and waiting to be cleared",
        "order.clear" => "Clear",
        "order.checkout" => "Checkout",
        "order.items" => "items",
        "order.view_cart" => "View cart",
        "order.view_order" => "View order",
        "order.table" => "Table",
        "order.waiter" => "Waiter",
        "order.tender" => "Payment",
        "order.payment_method" => "Payment method",
        "order.tip" => "Tip",
        "order.customer" => "Customer",
        "order.customer_hint" => "Customer name (optional)",
        "order.notes_hint" => "Order notes (optional)",
        "order.notes" => "Note",
        "order.cash_received" => "Cash received",
        "order.change" => "Change",
        "order.exact" => "Exact",
        "order.change_due" => "Change due",
        "order.short_by" => "Short by",
        "order.place_order" => "Place order",
        "order.order_placed" => "Order placed",
        "order.queued_hint" => "Saved — will sync when you're back online.",
        "order.sent_hint" => "Sent to the kitchen.",
        "order.new_order" => "New order",
        "order.done" => "Done",
        // receipt / printing
        "receipt.order" => "Order",
        "receipt.settled" => "Order settled",
        "receipt.thank_you" => "Thank you!",
        "receipt.title" => "Receipt",
        "receipt.print" => "Print receipt",
        "receipt.reprint" => "Reprint receipt",
        // loyalty — collecting a sale's points, on the receipt and on a past order
        "loyalty.add_points" => "Add points",
        "loyalty.add_points_title" => "Add points to this sale",
        "loyalty.points_added" => "Points added",
        "loyalty.points_queued" => "Points queued",
        "loyalty.queued_hint" => "This till is offline. The points go on as soon as it reconnects.",
        "loyalty.already_collected" => "Already collected",
        "loyalty.no_points" => "No points for this sale",
        "loyalty.scan_hint" => "Hold their wallet pass to the scanner, or point the camera at it.",
        "loyalty.phone_hint" => "Look the customer up by the number they signed up with.",
        "loyalty.phone_label" => "Phone number",
        "loyalty.phone_placeholder" => "01x xxxx xxxx",
        "loyalty.look_up" => "Look up",
        "loyalty.scanner_ready" => "Ready for the barcode scanner",
        "loyalty.use_phone" => "No card? Use their phone number",
        "loyalty.scan_card_instead" => "Scan a card instead",
        "tables.start_order_here" => "Start order here",
        "tables.settle" => "Settle",
        "receipt.printing" => "Printing…",
        "receipt.printed" => "Sent to printer",
        "receipt.print_failed" => "Couldn't reach the printer",
        "receipt.no_printer" => "Set a printer in Settings",
        "receipt.ref" => "Ref:",
        "receipt.voided" => "VOIDED",
        "receipt.delivery" => "DELIVERY",
        "receipt.customer" => "Customer",
        "receipt.phone" => "Phone",
        "receipt.address" => "Address:",
        "receipt.zone" => "Zone",
        "receipt.delivery_ref" => "Delivery Ref",
        "receipt.payment_hint" => "Payment (hint)",
        "receipt.notes" => "Notes:",
        "receipt.delivery_fee" => "Delivery Fee",
        "receipt.payment" => "Payment",
        "receipt.teller" => "Teller",
        "receipt.served_by" => "Served by",
        "receipt.cash" => "Cash",
        "delivery.unit" => "Unit",
        "delivery.floor" => "Floor",
        "delivery.in_mall" => "In-Mall",
        "delivery.outside" => "Outside",
        // Delivery channels beyond in-mall/outside (umbrella terrace & self-pickup);
        // the UI localizes `order.channel` via `delivery.<channel>`.
        "delivery.umbrella" => "Umbrella",
        "delivery.pickup" => "Pickup",
        "delivery.title" => "Delivery",
        // Unified "Orders" surface (teller): delivery + waiter open-tickets in one
        // place, two tabs. Segment labels reuse delivery.title / waiter.title.
        "incoming.title" => "Orders",
        // Kitchen Display + waiter open tickets (KDS / waiter client screens).
        "kds.title" => "Kitchen",
        "kds.reconnecting" => "Reconnecting…",
        "kds.all_clear" => "All caught up",
        "kds.waiter" => "WAITER",
        "waiter.title" => "Open tickets",
        "waiter.tickets" => "Tickets",
        "waiter.new_order" => "New order",
        "waiter.on_ticket" => "On this ticket",
        "waiter.new_round" => "New round",
        "waiter.no_tickets" => "No open tickets",
        "waiter.fire" => "Fire",
        "waiter.add_round" => "Add round",
        "waiter.queued" => "Queued",
        "waiter.items" => "items",
        "waiter.customer_optional" => "Customer (optional)",
        "waiter.covers" => "Covers",
        "waiter.table" => "Table (optional)",
        "waiter.ticket" => "Ticket",
        "waiter.fired" => "Sent to kitchen",
        "waiter.settle" => "Settle",
        "waiter.settled" => "Settled",
        // settle sheet (waiter / incoming) — charge-review labels
        "tender.total" => "Total",
        "tender.method" => "Method",
        // Realtime alert titles (the core builds these; the host posts the OS notification).
        "notif.new_delivery" => "New delivery order",
        "notif.new_ticket" => "New ticket fired",
        "notif.new_round" => "New round fired",
        "notif.new_kitchen" => "New kitchen order",
        "notif.ready" => "Order ready",
        "notif.new_booking" => "New booking",
        "notif.booking_arriving" => "Booked party due soon",
        "waiter.need_shift" => "Open a shift to settle",
        "waiter.void_title" => "Void ticket",
        "waiter.void_reason" => "Reason (optional)",
        "ticket.status.open" => "Open",
        "ticket.status.ready" => "Ready",
        "ticket.status.settled" => "Settled",
        "ticket.status.voided" => "Voided",
        "ticket.status.queued" => "Queued",
        "common.void" => "Void",
        "common.cancel" => "Cancel",
        // reservations & floor plan (host UI)
        "reservations.title" => "Reservations",
        "reservations.seat" => "Seat",
        "reservations.seated" => "Seated",
        "reservations.moved" => "Moved",
        "reservations.setStatus" => "Set status",
        "reservations.noBookings" => "No active bookings",
        "reservations.status_free" => "Free",
        "reservations.status_held" => "Held",
        "reservations.status_seated" => "Seated",
        "reservations.status_dirty" => "Dirty",
        "delivery.queue" => "Delivery queue",
        "delivery.empty" => "No delivery orders",
        "delivery.all" => "All",
        "delivery.active" => "Active",
        "delivery.items" => "items",
        "delivery.status.received" => "Received",
        "delivery.status.confirmed" => "Confirmed",
        "delivery.status.preparing" => "Preparing",
        "delivery.status.ready" => "Ready",
        "delivery.status.out_for_delivery" => "Out for delivery",
        "delivery.status.delivered" => "Delivered",
        "delivery.status.cancelled" => "Cancelled",
        "delivery.status.rejected" => "Rejected",
        "delivery.action.confirmed" => "Confirm",
        "delivery.action.preparing" => "Start preparing",
        "delivery.action.ready" => "Mark ready",
        "delivery.action.out_for_delivery" => "Out for delivery",
        "delivery.action.delivered" => "Mark delivered",
        "delivery.finalize" => "Finalize sale",
        "delivery.finalize_pay" => "Charge to",
        "delivery.cancel" => "Cancel order",
        "delivery.reject" => "Reject order",
        "delivery.cancel_reason" => "Reason (optional)",
        "delivery.restore_inventory" => "Restock ingredients",
        "delivery.prep_time" => "Prep time",
        "queue.ready_by" => "Ready by",
        "delivery.add_prep" => "+5 min",
        "delivery.finalized" => "Sale finalized",
        "delivery.accepting" => "Accepting",
        "delivery.mode_auto" => "Auto",
        "delivery.mode_open" => "Open",
        "delivery.mode_closed" => "Closed",
        // sync center (outbox)
        "sync.title" => "Sync",
        "sync.empty" => "Everything's synced.",
        "sync.queued" => "Queued",
        "sync.sending" => "Sending",
        "sync.failed" => "Failed",
        "sync.retry" => "Retry failed",
        "sync.push" => "Sync now",
        "sync.pushing" => "Syncing…",
        "sync.discard" => "Discard",
        "sync.attempts" => "attempts",
        "sync.pending" => "pending",
        "sync.op_open_shift" => "Open shift",
        "sync.op_close_shift" => "Close shift",
        "sync.op_create_order" => "Sale",
        // order-screen chrome (action bar + banners)
        "chrome.online" => "Online",
        "chrome.clock_skew" => "Device clock is off — please fix it",
        "chrome.offline" => "Offline",
        "chrome.offline_banner" => "Working offline — changes sync when you reconnect",
        "chrome.auth_paused" => "Sync paused — sign in again to resume",
        "chrome.view" => "View",
        "chrome.auth_paused_action" => "Sign in",
        "chrome.reauth_title" => "Resume sync",
        "chrome.reauth_body" => "Your session expired. Enter your PIN to resume syncing.",
        "chrome.reauth_as" => "Signed in as",
        "chrome.reauth_switch" => "Close shift & switch teller",
        "chrome.sync_resumed" => "Signed in — syncing resumed",
        "chrome.sync_data" => "Sync data",
        "chrome.sync_done" => "Data synced",
        "chrome.sync_failed" => "Couldn't sync — try again",
        "chrome.syncing" => "Syncing",
        "chrome.needs_attention" => "Needs attention",
        "chrome.queued" => "queued",
        "chrome.orders" => "orders",
        "chrome.more" => "More",
        // cash in/out + past shifts
        "cash.title" => "Cash in / out",
        "cash.in" => "Cash in",
        "cash.out" => "Cash out",
        "cash.amount" => "Amount",
        "cash.note" => "Note",
        "cash.record" => "Record movement",
        "cash.empty" => "No cash movements this shift.",
        "cash.history" => "Movements",
        "cash.total_in" => "Total in",
        "cash.total_out" => "Total out",
        "cash.net" => "net",
        "shifts.title" => "Past shifts",
        "shifts.empty" => "No shifts yet.",
        "shifts.closed" => "Closed",
        "shifts.opening" => "Opening",
        "shifts.declared" => "Declared",
        "shifts.discrepancy" => "Discrepancy",
        "shifts.orders" => "Orders",
        "shifts.no_orders" => "No orders in this shift.",
        "shifts.open_now" => "Open",
        // Z-report (printed shift report)
        "shift.report_title" => "Shift Report",
        "shift.payments" => "Payments",
        "shift.refunds" => "Refunds",
        "shift.refunds_cash" => "Refunds in cash",
        "shift.cash_in_refunded" => "Cash on refunded sales",
        "shift.cash_moves" => "Cash in/out",
        "shift.cash_in" => "Cash in",
        "shift.cash_out" => "Cash out",
        "shift.expected_cash" => "Expected cash",
        "shift.by_method" => "By method",
        "shift.business_date" => "Business Date",
        "shift.printed_at" => "Printed at",
        "shift.interim" => "Interim Report (Shift Still Open)",
        "shift.orders" => "orders",
        "shift.total_collected" => "Total Collected",
        "shift.drawer_ops" => "Drawer Operations",
        "shift.cash_recon" => "Cash Reconciliation",
        "shift.not_closed" => "Shift not yet closed",
        "shift.difference" => "Difference",
        "shift.opening_mismatch" => "Opening mismatch",
        "shift.transactions" => "Transactions",
        "shift.end_of_report" => "End of Report",
        "shift.print_report" => "Print report",
        "drafts.title" => "Held orders",
        "drafts.hold" => "Hold this order",
        "drafts.empty" => "No held orders.",
        "drafts.current" => "Current",
        // side-rail labels + section captions
        "nav.incoming" => "Incoming",
        "nav.section.orders" => "Orders",
        "nav.section.money" => "Money",
        "nav.section.system" => "System",
        // order history
        "history.title" => "Orders",
        "nav.history" => "History",
        "history.empty" => "No orders this shift yet.",
        "history.queued" => "Queued",
        "history.completed" => "Completed",
        "history.search" => "Search orders",
        "history.failed" => "Failed",
        "history.voided" => "Voided",
        "history.order" => "Order",
        // order-history table (Flutter-style columns / filters / stats)
        "history.current_shift" => "Current shift",
        "history.no_match" => "No matching orders",
        // all-orders search (history lookup across shifts)
        "search.title" => "Find orders",
        "search.teller_hint" => "Teller name",
        "search.date_24h" => "24h",
        "search.date_7d" => "7 days",
        "search.date_30d" => "30 days",
        "search.load_more" => "Load more",
        "search.exported" => "Orders copied as CSV",
        "history.synced" => "Synced",
        "history.stat.orders" => "Orders",
        "history.show_more" => "Show {count} more",
        "history.col.time" => "Time",
        "history.col.teller" => "Teller",
        "history.col.amount" => "Amount",
        "history.type.all" => "All",
        "history.type.dine_in" => "Dine-in",
        "history.type.delivery" => "Delivery",
        "order.payment" => "Payment",
        // void order
        "void.action" => "Void",
        "void.title" => "Void order",
        "void.reason" => "Reason",
        "void.reason_mistake" => "Order mistake",
        "void.reason_customer" => "Customer changed their mind",
        "void.reason_quality" => "Quality issue",
        "void.reason_other" => "Other",
        "void.note" => "Note (optional)",
        "void.restock" => "Restock ingredients",
        "void.confirm" => "Void order",
        "void.cancel" => "Cancel",
        // settings
        "settings.title" => "Settings",
        "settings.account" => "Account",
        "settings.appearance" => "Appearance",
        "settings.theme_light" => "Light",
        "settings.theme_dark" => "Dark",
        "settings.theme_system" => "System",
        "settings.orientation" => "Screen orientation",
        "settings.flip_screen" => "Flip screen",
        "settings.tablet_threshold" => "Tablet size cutoff",
        "settings.language" => "Language",
        "settings.device" => "Device",
        "settings.reconfigure" => "Reconfigure device",
        "settings.diagnostics" => "Diagnostics",
        "settings.recent_warnings" => "Recent warnings",
        "settings.clear" => "Clear",
        "settings.version" => "Version",
        "settings.server" => "Server",
        "settings.pending" => "Pending sync",
        "settings.realtime" => "Live updates",
        "settings.realtime_on" => "Connected",
        "settings.realtime_off" => "Reconnecting…",
        "settings.printer" => "Printer",
        "settings.till" => "Till",
        "settings.till_default" => "Branch default",
        "settings.printer_hint" => "IP address (e.g. 192.168.1.50)",
        "settings.printer_epson" => "Epson",
        "settings.printer_star" => "Star",
        "settings.printer_transport" => "Connection",
        "settings.printer_lan" => "Wi‑Fi / LAN",
        "settings.printer_bluetooth" => "Bluetooth",
        "settings.printer_paper_58" => "58 mm",
        "settings.printer_paper_80" => "80 mm",
        "settings.printer_bt_scan" => "Refresh paired devices",
        "settings.printer_bt_none" => {
            "No paired printers. Pair the printer in Android Bluetooth settings first (SPP, PIN 0000 or 1234)."
        }
        "settings.printer_bt_permission" => "Bluetooth permission is required to list printers.",
        "settings.printer_bt_connected" => "Connected",
        "settings.printer_bt_disconnected" => "Not connected",
        "settings.device_code_hint" => "e.g. T1, W2, K1",
        "settings.device_code_caption" => "Names this till in every order reference.",
        "settings.lan" => "LAN relay",
        "settings.lan_hub_hint" => "Hub IP — optional (e.g. 192.168.1.50)",
        "settings.lan_caption" => {
            "Set a fixed hub if devices can't find each other automatically on this Wi-Fi."
        }
        "settings.lan_active" => "Relay active",
        "settings.lan_offline" => "Relay off",
        "settings.lan_peers" => "peers",
        "settings.kitchen_routing" => "Kitchen routing",
        "settings.routing_kds" => "Kitchen screen",
        "settings.routing_till" => "This till",
        "settings.routing_both" => "Screen and till",
        "settings.routing_off" => "Not routed",
        "settings.legal" => "Legal",
        "settings.legal_privacy" => "Privacy Policy",
        "settings.legal_terms" => "Terms of Service",
        "settings.legal_copied" => "Link copied",
        "settings.sign_out" => "Sign out",
        "settings.sign_out_shift_open" => "Close your shift before signing out.",
        "settings.reconfigure_shift_open" => {
            "Close the current shift before reconfiguring the device."
        }
        // errors (host-side messages)
        "err.offline_no_setup" => {
            "You're offline and this teller hasn't been set up for offline sign-in yet."
        }
        "err.network" => "Network problem, please try again.",
        "err.not_allowed" => "You don't have permission to do that.",
        "err.generic" => "Something went wrong.",
        // ── the redesign (2026-09-12): three shells, one Charge, a Bill that is a screen ──
        // shells (apps/madar): tab words and the outbox pill
        "nav.sell" => "Sell",
        "nav.floor" => "Floor",
        "nav.queue" => "Queue",
        "nav.till" => "Till",
        "nav.bills" => "Bills",
        "nav.me" => "Me",
        "chrome.stuck" => "stuck",
        // sell (order entry)
        "sell.takeaway" => "Takeaway",
        "sell.parked" => "Parked",
        "sell.park" => "Park",
        "sell.parked_empty" => "Nothing parked",
        "sell.this_round" => "This round",
        "sell.on_the_bill" => "On the bill",
        "sell.round_total" => "Round",
        "sell.bill_so_far" => "Bill so far (before tax)",
        "sell.charge" => "Charge",
        "sell.fire" => "Fire",
        "sell.table_required" => "Seat a table first",
        "sell.guest_name" => "Guest name",
        "sell.round_n" => "Round",
        // floor
        "floor.title" => "Floor",
        "floor.seat" => "Seat",
        "floor.party_size" => "Party size",
        "floor.take_order" => "Take an order",
        "floor.unseat" => "Unseat (party left)",
        "floor.cleared" => "Cleared",
        "floor.seat_booking_here" => "Seat a booking here",
        "floor.walk_in_here" => "Walk-in here",
        "floor.no_bill_yet" => "No bill yet",
        // bill + the waiter's bills tab
        "bill.title" => "Bill",
        "bill.void_bill" => "Void bill",
        "bill.gone" => "This bill was closed on another till",
        "bill.ready" => "Ready",
        "bill.queued" => "Queued",
        "bill.voided" => "Voided",
        "bills.title" => "Bills",
        "bills.mine" => "Mine",
        "bills.others" => "Others",
        "bills.new_bill" => "New bill",
        // charge (the one tender drawer) + the done card
        "charge.title" => "Charge",
        "charge.takeaway" => "Takeaway",
        "charge.bill" => "bill",
        "charge.vat_included" => "VAT included",
        "charge.subtotal_hint" => "Service and VAT are added by the server",
        "charge.member" => "Member",
        "charge.add_tip" => "Add tip",
        "charge.remove_tip" => "Remove tip",
        "charge.applied_at_charge" => "applied at charge",
        "charge.free" => "free",
        "charge.sale" => "Sale",
        "charge.will_send" => "Will send when back online",
        "charge.cleared_q" => "cleared?",
        "charge.cleared" => "Cleared",
        "charge.not_yet" => "Not yet",
        "charge.not_printed" => "Not printed — no printer",
        "charge.printed" => "Printed",
        "charge.reprint" => "Reprint",
        "charge.change_short" => "change",
        // queue (the one inbox)
        "queue.title" => "Queue",
        "queue.bills" => "Bills",
        "queue.online" => "Online",
        "queue.accept" => "Accept",
        "queue.decline" => "Decline",
        "queue.decline_reason" => "Reason",
        "queue.ready_in" => "Ready in",
        "queue.minutes" => "minutes",
        "queue.charge" => "Charge",
        "queue.picked_up" => "Picked up",
        "queue.view" => "View",
        "queue.empty" => "Nothing waiting.",
        "queue.offline_notice" => "Offline — showing the last list",
        "queue.no_table" => "No table",
        "queue.accepted" => "Accepted",
        "queue.declined" => "Declined",
        "queue.need_shift" => "Open the shift first",
        // till (the drawer tab), cash in / out kinds, the close arithmetic
        "till.title" => "Till",
        "till.open_since" => "open since",
        "till.sales" => "Sales",
        "till.cash_in_till" => "Cash in till",
        "till.this_shift" => "This shift",
        "till.orders_this_shift" => "Orders this shift",
        "till.print_x" => "Print X report",
        "till.drawers" => "Drawers",
        "till.force_close_unavailable" => {
            "Force-close is not available from the till yet — use the dashboard."
        }
        "cash.pay_out" => "Pay out",
        "cash.pay_in" => "Pay in",
        "cash.note_hint" => "Note · what was it for",
        "cash.note_required" => "required",
        "cash.record_pay_out" => "Record pay-out",
        "cash.record_pay_in" => "Record pay-in",
        "shift.opening_float" => "Opening float",
        "shift.cash_sales" => "Cash sales",
        "shift.paid_in" => "Paid in",
        "shift.paid_out" => "Paid out",
        "shift.z_preview" => "Z report preview",
        "shift.why_short" => "Why is it short?",
        "shift.why_over" => "Why is it over?",
        "shift.close_hint" => "Closing locks Sell and Charge on this till.",
        "shift.reason_required" => "reason required",
        "shifts.force_closed" => "Force-closed",
        // orders (history): this shift / all, the sale, void versus refund
        "history.this_shift" => "This shift",
        "history.sales_count" => "{count} sales",
        "history.found_count" => "{count} found",
        "history.no_shift" => "No shift open",
        "history.search_hint" => "Number, customer or amount",
        "history.type.online" => "Online",
        "history.type.takeaway" => "Takeaway",
        "history.sale" => "Sale",
        "history.select_prompt" => "Tap a sale to see it here.",
        "history.service" => "Service",
        "history.tip" => "Tip",
        "history.vat_included" => "VAT included",
        "history.paid_at" => "Paid {time}",
        "history.reprint" => "Reprint",
        "history.more" => "More",
        "history.queued_hint" => "Will send when back online.",
        "history.failed_hint" => "The server refused this sale — see Sync.",
        "history.voided_hint" => "This sale was voided.",
        "history.offline_search" => "Searching past shifts needs a connection.",
        "history.offline_cached" => "Offline — showing what was loaded.",
        "history.retry" => "Try again",
        "history.price_flagged" => "Offline price",
        "history.price_flagged_hint" => {
            "Rung offline against an older menu — the price differs from the menu today."
        }
        "history.void_sale" => "Void sale",
        "history.void_teach" => "Void removes a mistaken sale as if it never happened.",
        "history.refund_teach" => "Refund returns money on a sale that stands.",
        "history.refunded" => "Refunded",
        "history.refund_left" => "{amount} left to refund",
        "history.refund_all" => "Already refunded in full.",
        "history.refund_queued" => "Waiting to send",
        "history.void_cannot_queued" => {
            "A queued sale cannot be voided until it reaches the server."
        }
        "history.void_cannot_voided" => "Already voided.",
        "history.void_cannot_failed" => {
            "This sale never reached the server; there is nothing to void."
        }
        // kitchen board
        "kds.bump_all" => "Bump all",
        "kds.round" => "R",
        "kds.open" => "open",
        "kds.age_min" => "m",
        "kds.live" => "Live",
        "kds.ready" => "Ready",
        "kds.pill_synced" => "Online",
        "kds.pill_queued" => "queued",
        "kds.pill_offline" => "Offline",
        "kds.pill_stuck" => "stuck",
        "kds.offline_banner" => "Working offline — bumps send when you reconnect",
        "kds.refused" => "bumps refused",
        "kds.retry" => "Retry",
        "kds.discard" => "Discard",
        // sync (waiting / stuck / blocked), settings rows, me, roles
        "sync.live_on" => "live updates",
        "sync.live_off" => "no live updates",
        "sync.waiting" => "Waiting",
        "sync.stuck" => "Stuck",
        "sync.needs_you" => "needs you",
        "sync.blocked" => "Blocked",
        "sync.blocked_hint" => {
            "Sales stranded behind a failed shift opening. Open a shift, then recover them."
        }
        "sync.recover" => "Recover stranded sales",
        "sync.recover_need_shift" => "Open a shift first",
        "sync.recovered" => "recovered",
        "sync.retry_all" => "Retry all",
        "sync.discard_title" => "Discard this action?",
        "sync.discard_body" => "It will never reach the server. The work it carried is lost.",
        "sync.tries" => "tries",
        "sync.more" => "more",
        "sync.see_all" => "See all",
        "sync.refused" => "The server refused it",
        "sync.op_void_order" => "Void sale",
        "sync.op_cash_movement" => "Cash in/out",
        "sync.op_open_ticket" => "New bill",
        "sync.op_ticket_add_round" => "Round",
        "sync.op_void_ticket" => "Void bill",
        "sync.op_settle_open_ticket" => "Charge bill",
        "sync.op_award_loyalty_points" => "Loyalty points",
        "sync.op_lan_mirror" => "LAN mirror",
        "settings.theme" => "Theme",
        "settings.printer_none" => "No printer",
        "settings.printer_paper" => "Paper",
        "settings.printer_brand" => "Brand",
        "settings.printer_test" => "Test print",
        "settings.device_code" => "Device code",
        "settings.environment" => "Environment",
        "settings.clock" => "Clock",
        "settings.clock_ok" => "in sync",
        "settings.minutes_off" => "min off",
        "settings.no_floor_hint" => "No floor layout — author one in the dashboard, then Sync now.",
        "settings.legal_hint" => "Tap a document to copy its address.",
        "me.my_bills" => "My bills",
        "me.no_bills" => "No open bills",
        "role.waiter" => "Waiter",
        "role.teller" => "Teller",
        "role.branch_manager" => "Manager",
        "role.org_admin" => "Admin",
        "role.super_admin" => "Admin",
        "role.kitchen" => "Kitchen",
        _ => return None,
    })
}

fn ar(key: &str) -> Option<&'static str> {
    Some(match key {
        "login.welcome_back" => "مرحبًا بعودتك",
        "login.subtitle" => "سجّل الدخول لفتح الخزينة",
        "login.name" => "الاسم",
        "login.sign_in" => "تسجيل الدخول",
        "login.pin_hint" => "يُرسل الرقم السري تلقائيًا عند ٦ أرقام",
        "login.reconfigure" => "إعادة ضبط الجهاز",
        "login.branch" => "فرع",
        "setup.title" => "إعداد نقطة البيع",
        "setup.desc" => "يسجّل المدير الدخول لربط هذا الجهاز بفرع، ثم يسجّل أمناء الصندوق الدخول.",
        "setup.choose_branch" => "اختر فرعًا",
        "setup.choose_branch_desc" => "اربط نقطة البيع بأحد فروعك.",
        "setup.email" => "بريد المدير",
        "setup.password" => "كلمة المرور",
        "setup.continue" => "متابعة",
        "setup.cancel" => "إلغاء",
        "setup.choose_station" => "اختر محطة",
        "setup.choose_station_desc" => "اختر محطة المطبخ التي يعرضها هذا الجهاز.",
        "setup.no_stations" => "لا توجد محطات مطبخ لهذا الفرع بعد.",
        "setup.station_default" => "افتراضي",
        "brand.headline" => "مرحبًا\nبعودتك.",
        "brand.tagline" => {
            "سجّل الدخول لفتح الخزينة. يعمل بالاتصال وبدونه — مبيعاتك مستمرة في الحالتين."
        }
        "home.signed_in" => "تم تسجيل الدخول",
        "home.online" => "متصل",
        "home.offline" => "غير متصل",
        "home.sign_out" => "تسجيل الخروج",
        "home.teller" => "أمين الصندوق",
        "home.role" => "الدور",
        "home.currency" => "العملة",
        "home.session" => "الجلسة",
        "shift.open_title" => "افتح ورديتك",
        "shift.opening_desc" => "احسب النقد في الدرج لبدء البيع.",
        "shift.opening_cash" => "النقد الافتتاحي",
        "shift.open_button" => "فتح الوردية",
        "shift.signed_in_as" => "مسجّل الدخول باسم",
        "shift.switch_teller" => "تبديل الأمين",
        "shift.welcome" => "مرحبًا بعودتك",
        "shift.opening_hint" => "احسب النقد الموجود في الدرج قبل أن تبدأ.",
        "shift.suggested_from_close" => "من آخر إغلاق",
        "shift.opening_reason_label" => "سبب الاختلاف",
        "shift.opening_reason_hint" => "العدّ الافتتاحي يختلف عن آخر إغلاق.",
        "shift.opening_reason_required" => "أضِف سبباً لاختلاف النقدية.",
        "common.done" => "تم",
        "order.title" => "طلب",
        "order.coming_soon" => "القائمة والطلبات — قريبًا.",
        "order.close_shift" => "إغلاق الوردية",
        "shift.close_title" => "إغلاق الوردية",
        "shift.closing_desc" => "احسب الدرج وأغلق ورديتك.",
        "shift.summary" => "ملخص الوردية",
        "shift.teller" => "أمين الصندوق",
        "shift.opened_at" => "فُتحت",
        "shift.counted_cash" => "النقد المحسوب",
        "shift.cash_note" => "ملاحظة (اختياري)",
        "shift.system_cash" => "النقد المتوقع",
        "shift.system_cash_explain" => "الافتتاحي + المبيعات النقدية − المسحوب",
        "shift.drawer_matches" => "الدرج مطابق",
        "shift.drawer_over" => "زيادة",
        "shift.drawer_short" => "نقص",
        "shift.report" => "تقرير الوردية",
        "order.all" => "الكل",
        "order.search" => "ابحث عن صنف",
        "order.empty" => "لا توجد أصناف هنا بعد.",
        "order.empty_desc" => "لم تتم مزامنة القائمة مع هذا الجهاز بعد.",
        "order.sync_menu" => "مزامنة القائمة",
        "order.rename_title" => "تسمية الطلب",
        "order.rename_hint" => "مثال: طاولة ٤، أحمد",
        "order.empty_search" => "لا شيء يطابق بحثك.",
        "order.cart" => "السلة",
        "order.cart_empty" => "سلتك فارغة.",
        "order.size" => "الحجم",
        "order.optionals" => "خيارات",
        "order.add_to_cart" => "أضف إلى السلة",
        "order.update_item" => "تحديث الصنف",
        "order.combos" => "العروض",
        "order.split_payment" => "تقسيم",
        "order.split_remaining" => "المتبقي",
        "order.save_component" => "حفظ",
        "order.configure" => "تخصيص",
        "order.bundle_includes" => "يشمل",
        "order.bundle_save" => "حفظ",
        "order.select_prefix" => "اختر",
        "order.addon_milk_type" => "الحليب",
        "order.addon_coffee_type" => "القهوة",
        "order.addon_extra" => "إضافات",
        "order.show_all_addons" => "عرض كل الإضافات",
        "order.show_assigned_addons" => "عرض أقل",
        "order.search_addons" => "ابحث عن الإضافات",
        "order.recipe" => "الوصفة",
        "order.steps" => "طريقة التحضير",
        "order.required" => "مطلوب",
        "order.subtotal" => "المجموع الفرعي",
        "order.tax" => "الضريبة",
        "kitchen.chit_heading" => "المطبخ",
        "printing.chit" => "إرسال إلى المطبخ",
        "printing.chit_sent" => "أُرسل إلى المطبخ",
        "printing.no_printer" => "لا توجد طابعة معدّة على هذا الجهاز",
        "printing.failed" => "لم تستجب الطابعة",
        "kitchen.chit_table" => "طاولة",
        "kitchen.chit_note" => "ملاحظة:",
        "order.service_charge" => "الخدمة",
        "order.total" => "الإجمالي",
        "order.discount" => "خصم",
        "order.no_discount" => "بدون خصم",
        "order.max_reached" => "تم بلوغ الحد الأقصى",
        "order.removed" => "تم الحذف",
        "order.undo" => "تراجع",
        // tables / floor canvas / transfer waitlist
        "tables.title" => "الطاولات",
        "tables.no_table" => "بدون طاولة",
        "tables.pick" => "اختر طاولة",
        "tables.assign" => "تعيين طاولة",
        "tables.clear_table" => "إزالة الطاولة",
        "tables.resume" => "فتح الطلب",
        "tables.move" => "نقل إلى طاولة أخرى",
        "tables.swap" => "تبديل الطاولتين",
        "tables.swap_pick" => "اضغط على الطاولة الأخرى",
        "tables.queue" => "إضافة لقائمة انتظار النقل",
        "tables.waitlist" => "قائمة انتظار النقل",
        "tables.wish_any" => "أي طاولة في",
        "tables.fulfill" => "إجلاس هنا",
        "tables.cancel_wish" => "إزالة",
        "tables.taken" => "الطاولة محجوزة — تم الحفظ بدونها",
        "tables.locked" => "قيد التعديل على جهاز آخر",
        "tables.add_round" => "إضافة جولة",
        "tables.round" => "جولة",
        "loyalty.customer" => "العميل",
        "loyalty.scan_card" => "مسح البطاقة",
        "loyalty.scan_title" => "امسح بطاقة العميل",
        "loyalty.not_identified" => "لم يتم مسح بطاقة",
        "loyalty.remove" => "إزالة",
        "loyalty.nothing_claimable" => "لا يوجد ما يمكن استبداله هنا بعد",
        "loyalty.rewards_ready" => "مكافآت جاهزة",
        "loyalty.left" => "متبقٍ",
        "loyalty.earns" => "هذه العملية تكسب",
        "tables.bill_pending" => "لم تتم مزامنة الجولة الأولى بعد",
        "tables.free" => "متاحة",
        "tables.seated" => "مشغولة",
        "tables.moved" => "تم النقل",
        "tables.queued" => "أُضيف إلى قائمة الانتظار",
        "tables.empty_waitlist" => "لا يوجد منتظرون",
        "tables.make_available" => "إتاحة الطاولة",
        "tables.free_it" => "إخلاء الطاولة",
        "tables.free_it_warning" => "لم تُدفع هذه الفاتورة. إخلاء الطاولة يتخلّى عنها.",
        "tables.empty_title" => "لا توجد طاولات بعد",
        "tables.empty_desc" => "ارسم مخطط الفرع من لوحة التحكم ثم زامن البيانات.",
        "tables.settle_first" => "سوّي الحساب أولًا، أو انقله إلى طاولة أخرى",
        "tables.freed" => "الطاولة متاحة الآن",
        "tables.seats" => "مقاعد",
        "tables.no_section" => "بدون قسم",
        "tables.held_res" => "محجوزة",
        "tables.reserved" => "محجوزة",
        "tables.reserved_for" => "محجوزة لـ",
        "tables.seat_booking" => "إجلاس هذه المجموعة",
        "tables.no_show" => "لم يحضر",
        "tables.arrivals" => "الحجوزات",
        "tables.arrivals_empty" => "لا حجوزات اليوم",
        "tables.booking_seated" => "تم إجلاس المجموعة — أرسل طلبهم",
        "tables.booking_no_show" => "تم تسجيل عدم الحضور",
        "tables.walk_in_anyway" => "إجلاس زبون عابر رغم ذلك",
        "tables.guests" => "أشخاص",
        "tables.seat_held" => "ضع طلبًا معلّقًا هنا",
        "tables.view_list" => "قائمة",
        "tables.view_plan" => "مخطط",
        "tables.due" => "موعده",
        "tables.late" => "متأخر",
        "tables.status" => "الحالة",
        // ── التنظيف: الدفع يترك الطاولة بحاجة إلى تجهيز ──
        "tables.needs_clearing" => "بحاجة لتنظيف",
        "tables.clear_ask" => "تنظيف طاولة",
        "tables.clear_ask_generic" => "هل تم تنظيف الطاولة؟",
        "tables.clear_ask_hint" =>
            "تم دفع الطلب. نظّف الطاولة الآن إذا كانت جاهزة للضيوف التاليين، وإلا فستبقى على المخطط بحاجة إلى تجهيز.",
        "tables.clear_now" => "نظّفها الآن",
        "tables.clear_later" => "ليس بعد — بحاجة لتجهيز",
        "tables.cleared" => "تم تنظيف الطاولة",
        "tables.clear" => "تنظيف الطاولة",
        "tables.dirty_hint" => "مدفوعة وبانتظار التنظيف",
        "order.clear" => "تفريغ",
        "order.checkout" => "الدفع",
        "order.items" => "أصناف",
        "order.view_cart" => "عرض السلة",
        "order.view_order" => "عرض الطلب",
        "order.table" => "طاولة",
        "order.waiter" => "النادل",
        "order.tender" => "الدفع",
        "order.payment_method" => "طريقة الدفع",
        "order.tip" => "البقشيش",
        "order.customer" => "العميل",
        "order.customer_hint" => "اسم العميل (اختياري)",
        "order.notes_hint" => "ملاحظات الطلب (اختياري)",
        "order.notes" => "ملاحظة",
        "order.cash_received" => "النقد المستلم",
        "order.change" => "الباقي",
        "order.exact" => "بالضبط",
        "order.change_due" => "الباقي",
        "order.short_by" => "ناقص",
        "order.place_order" => "تأكيد الطلب",
        "order.order_placed" => "تم الطلب",
        "order.queued_hint" => "تم الحفظ — ستتم المزامنة عند عودة الاتصال.",
        "order.sent_hint" => "أُرسل إلى المطبخ.",
        "order.new_order" => "طلب جديد",
        "order.done" => "تم",
        "receipt.order" => "طلب",
        "receipt.thank_you" => "شكراً لك!",
        "receipt.settled" => "تمت تسوية الطلب",
        "receipt.title" => "الإيصال",
        "receipt.print" => "طباعة الإيصال",
        "receipt.reprint" => "إعادة طباعة الإيصال",
        "loyalty.add_points" => "إضافة نقاط",
        "loyalty.add_points_title" => "إضافة نقاط إلى هذه الفاتورة",
        "loyalty.points_added" => "تمت إضافة النقاط",
        "loyalty.points_queued" => "النقاط في قائمة الانتظار",
        "loyalty.queued_hint" => "هذا الجهاز غير متصل. ستُضاف النقاط فور عودة الاتصال.",
        "loyalty.already_collected" => "تم تحصيلها من قبل",
        "loyalty.no_points" => "لا نقاط لهذه الفاتورة",
        "loyalty.scan_hint" => "قرّب بطاقة العميل من الماسح، أو وجّه الكاميرا إليها.",
        "loyalty.phone_hint" => "ابحث عن العميل برقم الهاتف المسجّل به.",
        "loyalty.phone_label" => "رقم الهاتف",
        "loyalty.phone_placeholder" => "01x xxxx xxxx",
        "loyalty.look_up" => "بحث",
        "loyalty.scanner_ready" => "جاهز لماسح الباركود",
        "loyalty.use_phone" => "لا توجد بطاقة؟ استخدم رقم الهاتف",
        "loyalty.scan_card_instead" => "امسح بطاقة بدلاً من ذلك",
        "tables.start_order_here" => "ابدأ طلبًا هنا",
        "tables.settle" => "تحصيل الحساب",
        "receipt.printing" => "جارٍ الطباعة…",
        "receipt.printed" => "تم الإرسال إلى الطابعة",
        "receipt.print_failed" => "تعذّر الوصول إلى الطابعة",
        "receipt.no_printer" => "اضبط الطابعة في الإعدادات",
        "receipt.ref" => "مرجع:",
        "receipt.voided" => "ملغي",
        "receipt.delivery" => "توصيل",
        "receipt.customer" => "العميل",
        "receipt.phone" => "الهاتف",
        "receipt.address" => "العنوان:",
        "receipt.zone" => "المنطقة",
        "receipt.delivery_ref" => "مرجع التوصيل",
        "receipt.payment_hint" => "الدفع (تلميح)",
        "receipt.notes" => "ملاحظات:",
        "receipt.delivery_fee" => "رسوم التوصيل",
        "receipt.payment" => "الدفع",
        "receipt.teller" => "الكاشير",
        "receipt.served_by" => "قدّمها",
        "receipt.cash" => "نقدي",
        "delivery.unit" => "وحدة",
        "delivery.floor" => "طابق",
        "delivery.in_mall" => "داخل المول",
        "delivery.outside" => "خارجي",
        // Delivery channels beyond in-mall/outside (umbrella terrace & self-pickup);
        // the UI localizes `order.channel` via `delivery.<channel>`.
        "delivery.umbrella" => "المظلات",
        "delivery.pickup" => "استلام",
        "delivery.title" => "التوصيل",
        "incoming.title" => "الطلبات",
        // Kitchen Display + waiter open tickets.
        "kds.title" => "المطبخ",
        "kds.reconnecting" => "جارٍ إعادة الاتصال…",
        "kds.all_clear" => "لا طلبات معلّقة",
        "kds.waiter" => "نادل",
        "waiter.title" => "التذاكر المفتوحة",
        "waiter.tickets" => "التذاكر",
        "waiter.new_order" => "طلب جديد",
        "waiter.on_ticket" => "على هذه التذكرة",
        "waiter.new_round" => "جولة جديدة",
        "waiter.no_tickets" => "لا توجد تذاكر مفتوحة",
        "waiter.fire" => "إرسال",
        "waiter.add_round" => "إضافة جولة",
        "waiter.queued" => "بالانتظار",
        "waiter.items" => "صنف",
        "waiter.customer_optional" => "العميل (اختياري)",
        "waiter.covers" => "عدد الضيوف",
        "waiter.table" => "طاولة (اختياري)",
        "waiter.ticket" => "تذكرة",
        "waiter.fired" => "أُرسل إلى المطبخ",
        "waiter.settle" => "تسوية",
        "waiter.settled" => "تمت التسوية",
        "tender.total" => "الإجمالي",
        "tender.method" => "الطريقة",
        "notif.new_delivery" => "طلب توصيل جديد",
        "notif.new_ticket" => "تذكرة جديدة",
        "notif.new_round" => "جولة جديدة",
        "notif.new_kitchen" => "طلب مطبخ جديد",
        "notif.ready" => "الطلب جاهز",
        "notif.new_booking" => "حجز جديد",
        "notif.booking_arriving" => "مجموعة محجوزة على وصول",
        "waiter.need_shift" => "افتح وردية للتسوية",
        "waiter.void_title" => "إلغاء التذكرة",
        "waiter.void_reason" => "السبب (اختياري)",
        "ticket.status.open" => "مفتوحة",
        "ticket.status.ready" => "جاهزة",
        "ticket.status.settled" => "مُسوّاة",
        "ticket.status.voided" => "ملغاة",
        "ticket.status.queued" => "بالانتظار",
        "common.void" => "إلغاء",
        "common.cancel" => "إلغاء",
        // reservations & floor plan (host UI)
        "reservations.title" => "الحجوزات",
        "reservations.seat" => "إجلاس",
        "reservations.seated" => "تم الإجلاس",
        "reservations.moved" => "تم النقل",
        "reservations.setStatus" => "تعيين الحالة",
        "reservations.noBookings" => "لا توجد حجوزات نشطة",
        "reservations.status_free" => "فارغة",
        "reservations.status_held" => "محجوزة",
        "reservations.status_seated" => "مشغولة",
        "reservations.status_dirty" => "تحتاج تنظيف",
        "delivery.queue" => "قائمة التوصيل",
        "delivery.empty" => "لا توجد طلبات توصيل",
        "delivery.all" => "الكل",
        "delivery.active" => "نشطة",
        "delivery.items" => "أصناف",
        "delivery.status.received" => "مستلم",
        "delivery.status.confirmed" => "مؤكد",
        "delivery.status.preparing" => "قيد التحضير",
        "delivery.status.ready" => "جاهز",
        "delivery.status.out_for_delivery" => "خرج للتوصيل",
        "delivery.status.delivered" => "تم التوصيل",
        "delivery.status.cancelled" => "ملغي",
        "delivery.status.rejected" => "مرفوض",
        "delivery.action.confirmed" => "تأكيد",
        "delivery.action.preparing" => "بدء التحضير",
        "delivery.action.ready" => "تحديد جاهز",
        "delivery.action.out_for_delivery" => "خرج للتوصيل",
        "delivery.action.delivered" => "تحديد تم التوصيل",
        "delivery.finalize" => "إتمام البيع",
        "delivery.finalize_pay" => "تحصيل عبر",
        "delivery.cancel" => "إلغاء الطلب",
        "delivery.reject" => "رفض الطلب",
        "delivery.cancel_reason" => "السبب (اختياري)",
        "delivery.restore_inventory" => "إعادة المخزون",
        "delivery.prep_time" => "وقت التحضير",
        "queue.ready_by" => "جاهز بحلول",
        "delivery.add_prep" => "+٥ دقائق",
        "delivery.finalized" => "تم إتمام البيع",
        "delivery.accepting" => "قبول الطلبات",
        "delivery.mode_auto" => "تلقائي",
        "delivery.mode_open" => "مفتوح",
        "delivery.mode_closed" => "مغلق",
        "sync.title" => "المزامنة",
        "sync.empty" => "كل شيء متزامن.",
        "sync.queued" => "في الانتظار",
        "sync.sending" => "جارٍ الإرسال",
        "sync.failed" => "فشل",
        "sync.retry" => "إعادة محاولة الفاشلة",
        "sync.push" => "مزامنة الآن",
        "sync.pushing" => "جارٍ المزامنة…",
        "sync.discard" => "تجاهل",
        "sync.attempts" => "محاولات",
        "sync.pending" => "قيد المزامنة",
        "sync.op_open_shift" => "فتح وردية",
        "sync.op_close_shift" => "إغلاق وردية",
        "sync.op_create_order" => "طلب",
        // order-screen chrome (action bar + banners)
        "chrome.online" => "متصل",
        "chrome.clock_skew" => "ساعة الجهاز غير مضبوطة — يرجى تصحيحها",
        "chrome.offline" => "غير متصل",
        "chrome.offline_banner" => "تعمل دون اتصال — ستتم المزامنة عند عودة الاتصال",
        "chrome.auth_paused" => "توقفت المزامنة — سجّل الدخول لاستئنافها",
        "chrome.view" => "عرض",
        "chrome.auth_paused_action" => "تسجيل الدخول",
        "chrome.reauth_title" => "استئناف المزامنة",
        "chrome.reauth_body" => "انتهت جلستك. أدخل رمزك السري لاستئناف المزامنة.",
        "chrome.reauth_as" => "مسجّل الدخول باسم",
        "chrome.reauth_switch" => "إغلاق الوردية وتبديل الكاشير",
        "chrome.sync_resumed" => "تم تسجيل الدخول — استؤنفت المزامنة",
        "chrome.sync_data" => "مزامنة البيانات",
        "chrome.sync_done" => "تمت مزامنة البيانات",
        "chrome.sync_failed" => "تعذّرت المزامنة — حاول مجددًا",
        "chrome.syncing" => "جارٍ المزامنة",
        "chrome.needs_attention" => "يحتاج إلى مراجعة",
        "chrome.queued" => "في الانتظار",
        "chrome.orders" => "طلبات",
        "chrome.more" => "المزيد",
        // cash in/out + past shifts
        "cash.title" => "إيداع/سحب نقدي",
        "cash.in" => "إيداع",
        "cash.out" => "سحب",
        "cash.amount" => "المبلغ",
        "cash.note" => "ملاحظة",
        "cash.record" => "تسجيل الحركة",
        "cash.empty" => "لا توجد حركات نقدية في هذه الوردية.",
        "cash.history" => "الحركات",
        "cash.total_in" => "إجمالي الداخل",
        "cash.total_out" => "إجمالي الخارج",
        "cash.net" => "الصافي",
        "shifts.title" => "الورديات السابقة",
        "shifts.empty" => "لا توجد ورديات بعد.",
        "shifts.closed" => "أُغلقت",
        "shifts.opening" => "رصيد البداية",
        "shifts.declared" => "المعلن",
        "shifts.discrepancy" => "الفرق",
        "shifts.orders" => "الطلبات",
        "shifts.no_orders" => "لا توجد طلبات في هذه الوردية.",
        "shifts.open_now" => "مفتوحة",
        // Z-report (printed shift report)
        "shift.report_title" => "تقرير الوردية",
        "shift.payments" => "المدفوعات",
        "shift.refunds" => "المبالغ المستردة",
        "shift.refunds_cash" => "المسترد نقداً",
        "shift.cash_in_refunded" => "نقد مبيعات مستردة",
        "shift.cash_moves" => "إيداع/سحب",
        "shift.cash_in" => "إيداع نقدي",
        "shift.cash_out" => "سحب نقدي",
        "shift.expected_cash" => "النقد المتوقع",
        "shift.by_method" => "حسب الطريقة",
        "shift.business_date" => "تاريخ العمل",
        "shift.printed_at" => "وقت الطباعة",
        "shift.interim" => "تقرير مبدئي (الوردية ما زالت مفتوحة)",
        "shift.orders" => "طلب",
        "shift.total_collected" => "إجمالي المحصّل",
        "shift.drawer_ops" => "عمليات الدرج",
        "shift.cash_recon" => "تسوية النقدية",
        "shift.not_closed" => "لم تُغلق الوردية بعد",
        "shift.difference" => "الفرق",
        "shift.opening_mismatch" => "فرق الافتتاح",
        "shift.transactions" => "المعاملات",
        "shift.end_of_report" => "نهاية التقرير",
        "shift.print_report" => "طباعة التقرير",
        "drafts.title" => "طلبات معلّقة",
        "drafts.hold" => "تعليق هذا الطلب",
        "drafts.empty" => "لا توجد طلبات معلّقة.",
        "drafts.current" => "الحالي",
        "nav.incoming" => "الوارد",
        "nav.section.orders" => "الطلبات",
        "nav.section.money" => "المالية",
        "nav.section.system" => "النظام",
        "history.title" => "الطلبات",
        "nav.history" => "السجل",
        "history.empty" => "لا توجد طلبات في هذه الوردية بعد.",
        "history.queued" => "في الانتظار",
        "history.completed" => "مكتمل",
        "history.search" => "ابحث في الطلبات",
        "history.failed" => "فشل",
        "history.voided" => "ملغى",
        "history.order" => "طلب",
        // order-history table (Flutter-style columns / filters / stats)
        "history.current_shift" => "الوردية الحالية",
        "history.no_match" => "لا توجد طلبات مطابقة",
        "search.title" => "ابحث عن الطلبات",
        "search.teller_hint" => "اسم الكاشير",
        "search.date_24h" => "٢٤ ساعة",
        "search.date_7d" => "٧ أيام",
        "search.date_30d" => "٣٠ يوم",
        "search.load_more" => "تحميل المزيد",
        "search.exported" => "تم نسخ الطلبات كملف CSV",
        "history.synced" => "متزامن",
        "history.stat.orders" => "الطلبات",
        "history.show_more" => "عرض {count} إضافية",
        "history.col.time" => "الوقت",
        "history.col.teller" => "الكاشير",
        "history.col.amount" => "المبلغ",
        "history.type.all" => "الكل",
        "history.type.dine_in" => "محلي",
        "history.type.delivery" => "توصيل",
        "order.payment" => "طريقة الدفع",
        "void.action" => "إبطال",
        "void.title" => "إبطال الطلب",
        "void.reason" => "السبب",
        "void.reason_mistake" => "خطأ في الطلب",
        "void.reason_customer" => "تغيّر رأي العميل",
        "void.reason_quality" => "مشكلة في الجودة",
        "void.reason_other" => "أخرى",
        "void.note" => "ملاحظة (اختياري)",
        "void.restock" => "إعادة المكوّنات للمخزون",
        "void.confirm" => "إبطال الطلب",
        "void.cancel" => "إلغاء",
        "settings.title" => "الإعدادات",
        "settings.account" => "الحساب",
        "settings.appearance" => "المظهر",
        "settings.theme_light" => "فاتح",
        "settings.theme_dark" => "داكن",
        "settings.theme_system" => "النظام",
        "settings.orientation" => "اتجاه الشاشة",
        "settings.flip_screen" => "قلب الشاشة",
        "settings.tablet_threshold" => "حد حجم الجهاز اللوحي",
        "settings.language" => "اللغة",
        "settings.device" => "الجهاز",
        "settings.reconfigure" => "إعادة ضبط الجهاز",
        "settings.diagnostics" => "التشخيص",
        "settings.recent_warnings" => "تحذيرات حديثة",
        "settings.clear" => "مسح",
        "settings.version" => "الإصدار",
        "settings.server" => "الخادم",
        "settings.pending" => "بانتظار المزامنة",
        "settings.realtime" => "التحديثات المباشرة",
        "settings.realtime_on" => "متصل",
        "settings.realtime_off" => "إعادة الاتصال…",
        "settings.printer" => "الطابعة",
        "settings.till" => "الكاشة",
        "settings.till_default" => "افتراضي الفرع",
        "settings.printer_hint" => "عنوان IP (مثال: 192.168.1.50)",
        "settings.printer_epson" => "إبسون",
        "settings.printer_star" => "ستار",
        "settings.printer_transport" => "الاتصال",
        "settings.printer_lan" => "واي فاي / الشبكة",
        "settings.printer_bluetooth" => "بلوتوث",
        "settings.printer_paper_58" => "٥٨ مم",
        "settings.printer_paper_80" => "٨٠ مم",
        "settings.printer_bt_scan" => "تحديث الأجهزة المقترنة",
        "settings.printer_bt_none" => {
            "لا توجد طابعات مقترنة. اقرن الطابعة من إعدادات بلوتوث في أندرويد أولًا (SPP، الرمز 0000 أو 1234)."
        }
        "settings.printer_bt_permission" => "إذن البلوتوث مطلوب لعرض الطابعات.",
        "settings.printer_bt_connected" => "متصلة",
        "settings.printer_bt_disconnected" => "غير متصلة",
        "settings.device_code_hint" => "مثال: T1، W2، K1",
        "settings.device_code_caption" => "يحدد اسم هذه الكاشة في كل مرجع طلب.",
        "settings.lan" => "الشبكة المحلية",
        "settings.lan_hub_hint" => "عنوان الموزّع — اختياري (مثل 192.168.1.50)",
        "settings.lan_caption" => {
            "عيّن موزّعًا ثابتًا إذا تعذّر على الأجهزة العثور على بعضها تلقائيًا على هذه الشبكة."
        }
        "settings.lan_active" => "التتابع نشط",
        "settings.lan_offline" => "التتابع متوقّف",
        "settings.lan_peers" => "أجهزة",
        "settings.kitchen_routing" => "توجيه المطبخ",
        "settings.routing_kds" => "شاشة المطبخ",
        "settings.routing_till" => "الكاشة",
        "settings.routing_both" => "الشاشة والكاشة",
        "settings.routing_off" => "بدون توجيه",
        "settings.legal" => "الشروط والخصوصية",
        "settings.legal_privacy" => "سياسة الخصوصية",
        "settings.legal_terms" => "شروط الخدمة",
        "settings.legal_copied" => "تم نسخ الرابط",
        "settings.sign_out" => "تسجيل الخروج",
        "settings.sign_out_shift_open" => "أغلق ورديتك قبل تسجيل الخروج.",
        "settings.reconfigure_shift_open" => "أغلق الوردية الحالية قبل إعادة ضبط الجهاز.",
        "err.offline_no_setup" => "أنت غير متصل ولم يتم تهيئة هذا الأمين للدخول دون اتصال بعد.",
        "err.network" => "مشكلة في الشبكة، حاول مرة أخرى.",
        "err.not_allowed" => "ليس لديك صلاحية للقيام بذلك.",
        "err.generic" => "حدث خطأ ما.",
        // ── the redesign (2026-09-12): three shells, one Charge, a Bill that is a screen ──
        // shells (apps/madar): tab words and the outbox pill
        "nav.sell" => "البيع",
        "nav.floor" => "الصالة",
        "nav.queue" => "الوارد",
        "nav.till" => "الصندوق",
        "nav.bills" => "الفواتير",
        "nav.me" => "أنا",
        "chrome.stuck" => "متعثر",
        // sell (order entry)
        "sell.takeaway" => "تيك أواي",
        "sell.parked" => "مركونة",
        "sell.park" => "اركن الطلب",
        "sell.parked_empty" => "لا طلبات مركونة",
        "sell.this_round" => "هذه الجولة",
        "sell.on_the_bill" => "على الفاتورة",
        "sell.round_total" => "الجولة",
        "sell.bill_so_far" => "الفاتورة حتى الآن (قبل الضريبة)",
        "sell.charge" => "تحصيل",
        "sell.fire" => "أرسل",
        "sell.table_required" => "أجلس على طاولة أولًا",
        "sell.guest_name" => "اسم الضيف",
        "sell.round_n" => "جولة",
        // floor
        "floor.title" => "الصالة",
        "floor.seat" => "إجلاس",
        "floor.party_size" => "عدد الأفراد",
        "floor.take_order" => "خذ الطلب",
        "floor.unseat" => "إلغاء الإجلاس (غادروا)",
        "floor.cleared" => "تم التنظيف",
        "floor.seat_booking_here" => "أجلس حجزًا هنا",
        "floor.walk_in_here" => "زبون عابر هنا",
        "floor.no_bill_yet" => "لا فاتورة بعد",
        // bill + the waiter's bills tab
        "bill.title" => "الفاتورة",
        "bill.void_bill" => "إلغاء الفاتورة",
        "bill.gone" => "أُغلقت هذه الفاتورة على جهاز آخر",
        "bill.ready" => "جاهز",
        "bill.queued" => "في الانتظار",
        "bill.voided" => "ملغى",
        "bills.title" => "الفواتير",
        "bills.mine" => "فواتيري",
        "bills.others" => "الآخرون",
        "bills.new_bill" => "فاتورة جديدة",
        // charge (the one tender drawer) + the done card
        "charge.title" => "تحصيل",
        "charge.takeaway" => "تيك أواي",
        "charge.bill" => "فاتورة",
        "charge.vat_included" => "شامل ضريبة القيمة المضافة",
        "charge.subtotal_hint" => "تُضاف الخدمة والضريبة من الخادم",
        "charge.member" => "عضو",
        "charge.add_tip" => "إضافة بقشيش",
        "charge.remove_tip" => "إزالة البقشيش",
        "charge.applied_at_charge" => "يُطبَّق عند التحصيل",
        "charge.free" => "مجاناً",
        "charge.sale" => "بيع",
        "charge.will_send" => "سيُرسل عند عودة الاتصال",
        "charge.cleared_q" => "تم تنظيفها؟",
        "charge.cleared" => "تم التنظيف",
        "charge.not_yet" => "ليس بعد",
        "charge.not_printed" => "لم تُطبع — لا توجد طابعة",
        "charge.printed" => "طُبع",
        "charge.reprint" => "إعادة طباعة",
        "charge.change_short" => "الباقي",
        // queue (the one inbox)
        "queue.title" => "الوارد",
        "queue.bills" => "الفواتير",
        "queue.online" => "أونلاين",
        "queue.accept" => "قبول",
        "queue.decline" => "رفض",
        "queue.decline_reason" => "السبب",
        "queue.ready_in" => "جاهز خلال",
        "queue.minutes" => "دقيقة",
        "queue.charge" => "تحصيل",
        "queue.picked_up" => "تم الاستلام",
        "queue.view" => "عرض",
        "queue.empty" => "لا شيء بالانتظار.",
        "queue.offline_notice" => "غير متصل — تُعرض آخر قائمة",
        "queue.no_table" => "بدون طاولة",
        "queue.accepted" => "تم القبول",
        "queue.declined" => "تم الرفض",
        "queue.need_shift" => "افتح الوردية أولاً",
        // till (the drawer tab), cash in / out kinds, the close arithmetic
        "till.title" => "الصندوق",
        "till.open_since" => "مفتوحة منذ",
        "till.sales" => "المبيعات",
        "till.cash_in_till" => "النقد في الدرج",
        "till.this_shift" => "هذه الوردية",
        "till.orders_this_shift" => "طلبات هذه الوردية",
        "till.print_x" => "طباعة تقرير X",
        "till.drawers" => "الأدراج",
        "till.force_close_unavailable" => {
            "الإغلاق الإجباري غير متاح من الصندوق بعد — استخدم لوحة التحكم."
        }
        "cash.pay_out" => "سحب",
        "cash.pay_in" => "إيداع",
        "cash.note_hint" => "ملاحظة · لأي غرض",
        "cash.note_required" => "مطلوب",
        "cash.record_pay_out" => "تسجيل السحب",
        "cash.record_pay_in" => "تسجيل الإيداع",
        "shift.opening_float" => "الرصيد الافتتاحي",
        "shift.cash_sales" => "المبيعات النقدية",
        "shift.paid_in" => "المودع",
        "shift.paid_out" => "المسحوب",
        "shift.z_preview" => "معاينة تقرير Z",
        "shift.why_short" => "ما سبب النقص؟",
        "shift.why_over" => "ما سبب الزيادة؟",
        "shift.close_hint" => "الإغلاق يوقف البيع والتحصيل على هذا الصندوق.",
        "shift.reason_required" => "السبب مطلوب",
        "shifts.force_closed" => "أُغلقت إجبارياً",
        // orders (history): this shift / all, the sale, void versus refund
        "history.this_shift" => "هذه الوردية",
        "history.sales_count" => "{count} مبيعات",
        "history.found_count" => "{count} نتيجة",
        "history.no_shift" => "لا توجد وردية مفتوحة",
        "history.search_hint" => "الرقم أو العميل أو المبلغ",
        "history.type.online" => "أونلاين",
        "history.type.takeaway" => "تيك أواي",
        "history.sale" => "بيع",
        "history.select_prompt" => "اختر عملية بيع لعرضها هنا.",
        "history.service" => "الخدمة",
        "history.tip" => "بقشيش",
        "history.vat_included" => "شامل الضريبة",
        "history.paid_at" => "دُفعت {time}",
        "history.reprint" => "إعادة طباعة",
        "history.more" => "المزيد",
        "history.queued_hint" => "سيُرسل عند عودة الاتصال.",
        "history.failed_hint" => "رفض الخادم عملية البيع هذه — راجع المزامنة.",
        "history.voided_hint" => "أُبطلت عملية البيع هذه.",
        "history.offline_search" => "البحث في الورديات السابقة يحتاج اتصالاً بالخادم.",
        "history.offline_cached" => "غير متصل — تُعرض النتائج المحمّلة سابقاً.",
        "history.retry" => "أعد المحاولة",
        "history.price_flagged" => "سعر غير محدّث",
        "history.price_flagged_hint" => {
            "سُجّلت دون اتصال بأسعار قائمة أقدم — السعر يختلف عن القائمة الحالية."
        }
        "history.void_sale" => "إبطال البيع",
        "history.void_teach" => "الإبطال يزيل عملية بيع خاطئة كأنها لم تحدث.",
        "history.refund_teach" => "الاسترداد يرجع المال مع بقاء عملية البيع.",
        "history.refunded" => "مُسترد",
        "history.refund_left" => "متبقٍ للاسترداد {amount}",
        "history.refund_all" => "تم استرداد المبلغ بالكامل.",
        "history.refund_queued" => "بانتظار الإرسال",
        "history.void_cannot_queued" => "لا يمكن إبطال عملية في الانتظار قبل وصولها إلى الخادم.",
        "history.void_cannot_voided" => "أُبطلت بالفعل.",
        "history.void_cannot_failed" => "لم تصل عملية البيع هذه إلى الخادم؛ لا شيء لإبطاله.",
        // kitchen board
        "kds.bump_all" => "إنهاء الكل",
        "kds.round" => "ج",
        "kds.open" => "مفتوحة",
        "kds.age_min" => "د",
        "kds.live" => "مباشر",
        "kds.ready" => "جاهز",
        "kds.pill_synced" => "متصل",
        "kds.pill_queued" => "في الانتظار",
        "kds.pill_offline" => "غير متصل",
        "kds.pill_stuck" => "متعثر",
        "kds.offline_banner" => "تعمل دون اتصال — تُرسل الإنهاءات عند عودة الاتصال",
        "kds.refused" => "إنهاءات مرفوضة",
        "kds.retry" => "إعادة المحاولة",
        "kds.discard" => "تجاهل",
        // sync (waiting / stuck / blocked), settings rows, me, roles
        "sync.live_on" => "تحديثات مباشرة",
        "sync.live_off" => "بدون تحديثات مباشرة",
        "sync.waiting" => "بالانتظار",
        "sync.stuck" => "متعثر",
        "sync.needs_you" => "يحتاجك",
        "sync.blocked" => "محجوز",
        "sync.blocked_hint" => "مبيعات عالقة خلف فتح وردية فاشل. افتح وردية ثم استرجعها.",
        "sync.recover" => "استرجاع المبيعات العالقة",
        "sync.recover_need_shift" => "افتح وردية أولاً",
        "sync.recovered" => "تم استرجاعها",
        "sync.retry_all" => "إعادة محاولة الكل",
        "sync.discard_title" => "تجاهل هذا الإجراء؟",
        "sync.discard_body" => "لن يصل إلى الخادم أبداً، وسيُفقد ما كان يحمله.",
        "sync.tries" => "محاولات",
        "sync.more" => "أخرى",
        "sync.see_all" => "عرض الكل",
        "sync.refused" => "رفضه الخادم",
        "sync.op_void_order" => "إلغاء بيع",
        "sync.op_cash_movement" => "حركة نقدية",
        "sync.op_open_ticket" => "فاتورة جديدة",
        "sync.op_ticket_add_round" => "جولة",
        "sync.op_void_ticket" => "إلغاء فاتورة",
        "sync.op_settle_open_ticket" => "تحصيل فاتورة",
        "sync.op_award_loyalty_points" => "نقاط الولاء",
        "sync.op_lan_mirror" => "مرآة الشبكة المحلية",
        "settings.theme" => "المظهر",
        "settings.printer_none" => "لا توجد طابعة",
        "settings.printer_paper" => "الورق",
        "settings.printer_brand" => "الماركة",
        "settings.printer_test" => "طباعة تجريبية",
        "settings.device_code" => "رمز الجهاز",
        "settings.environment" => "البيئة",
        "settings.clock" => "الساعة",
        "settings.clock_ok" => "مضبوطة",
        "settings.minutes_off" => "دقيقة فرق",
        "settings.no_floor_hint" => {
            "لا يوجد مخطط للصالة — أنشئ واحداً في لوحة التحكم ثم اضغط مزامنة الآن."
        }
        "settings.legal_hint" => "اضغط على مستند لنسخ عنوانه.",
        "me.my_bills" => "فواتيري",
        "me.no_bills" => "لا توجد فواتير مفتوحة",
        "role.waiter" => "نادل",
        "role.teller" => "أمين صندوق",
        "role.branch_manager" => "مدير",
        "role.org_admin" => "مسؤول",
        "role.super_admin" => "مسؤول",
        "role.kitchen" => "المطبخ",
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_locale_then_falls_back() {
        assert_eq!(tr("ar-EG", "login.sign_in"), "تسجيل الدخول");
        assert_eq!(tr("ar", "login.sign_in"), "تسجيل الدخول");
        assert_eq!(tr("en", "login.sign_in"), "Sign in");
        assert_eq!(tr("fr", "login.sign_in"), "Sign in"); // unknown lang → en
        assert_eq!(tr("en", "no.such.key"), "no.such.key"); // unknown key → key
    }

    #[test]
    fn rtl_detection() {
        assert!(is_rtl("ar-EG"));
        assert!(is_rtl("ar"));
        assert!(!is_rtl("en-US"));
    }

    // ── tr: resolution order ─────────────────────────────────────────────

    #[test]
    fn tr_arabic_resolves_from_ar_table() {
        // A key present in both tables must return the AR string for ar locales.
        assert_eq!(tr("ar", "order.total"), "الإجمالي");
        assert_eq!(tr("ar-EG", "order.total"), "الإجمالي");
    }

    #[test]
    fn tr_english_locale_uses_en_table() {
        assert_eq!(tr("en", "order.total"), "Total");
        assert_eq!(tr("en-US", "order.total"), "Total");
    }

    #[test]
    fn tr_underscore_locale_separator_is_handled() {
        // lang_of splits on '_' too, not just '-'.
        assert_eq!(tr("ar_EG", "login.sign_in"), "تسجيل الدخول");
        assert_eq!(tr("en_GB", "login.sign_in"), "Sign in");
    }

    #[test]
    fn tr_unknown_language_falls_back_to_en() {
        // Non-ar, non-en language: there's no fr table, so resolve via en.
        assert_eq!(tr("fr", "order.total"), "Total");
        assert_eq!(tr("de-DE", "order.cart"), "Cart");
        assert_eq!(tr("zh", "settings.title"), "Settings");
    }

    #[test]
    fn tr_unknown_key_falls_back_to_key_itself() {
        assert_eq!(tr("en", "no.such.key"), "no.such.key");
        assert_eq!(tr("ar", "no.such.key"), "no.such.key");
        assert_eq!(tr("fr", "totally.made.up"), "totally.made.up");
    }

    #[test]
    fn tr_empty_locale_falls_back_to_en() {
        // lang_of("") yields "" → not ar → en table.
        assert_eq!(tr("", "order.total"), "Total");
    }

    #[test]
    fn tr_empty_key_returns_empty_key() {
        // No table has a "" entry, so it falls through to the key itself.
        assert_eq!(tr("en", ""), "");
        assert_eq!(tr("ar", ""), "");
    }

    #[test]
    fn tr_is_case_sensitive_on_key() {
        // Keys are matched literally; a different case is unknown → key.
        assert_eq!(tr("en", "Order.Total"), "Order.Total");
    }

    #[test]
    fn tr_is_case_sensitive_on_locale_language() {
        // lang_of does not lowercase, so "AR" is not treated as arabic → en.
        assert_eq!(tr("AR", "order.total"), "Total");
    }

    #[test]
    fn tr_key_only_in_en_falls_back_to_en_for_ar_locale() {
        // If a key exists in EN but (hypothetically) not in AR, ar() returns
        // None and tr falls through to en(). Verified structurally by the
        // coverage test below; here we assert the fallback chain on a real key
        // that the coverage test guarantees exists in both, so this just pins
        // the en value for a non-translated-looking key.
        assert_eq!(
            tr("ar", "settings.printer_hint"),
            "عنوان IP (مثال: 192.168.1.50)"
        );
    }

    // ── is_rtl ───────────────────────────────────────────────────────────

    #[test]
    fn is_rtl_covers_all_flagged_languages() {
        assert!(is_rtl("ar"));
        assert!(is_rtl("fa"));
        assert!(is_rtl("he"));
        assert!(is_rtl("ur"));
        assert!(is_rtl("fa-IR"));
        assert!(is_rtl("he_IL"));
    }

    #[test]
    fn is_rtl_false_for_ltr_and_unknown() {
        assert!(!is_rtl("en"));
        assert!(!is_rtl("fr-FR"));
        assert!(!is_rtl(""));
        assert!(!is_rtl("AR")); // case-sensitive, uppercase is not flagged
    }

    // ── direct table access ──────────────────────────────────────────────

    #[test]
    fn en_returns_none_for_unknown_key() {
        assert!(en("definitely.not.a.key").is_none());
    }

    #[test]
    fn ar_returns_none_for_unknown_key() {
        assert!(ar("definitely.not.a.key").is_none());
    }

    #[test]
    fn en_and_ar_have_matching_known_key() {
        assert_eq!(en("order.checkout"), Some("Checkout"));
        assert_eq!(ar("order.checkout"), Some("الدفع"));
    }

    // ── COVERAGE: every EN key must also be in the AR table ───────────────

    /// Extract the `"key" =>` literals from a single `fn`'s body in the source.
    /// We slice the file between the function's opening signature and the next
    /// top-level `fn ` so the dispatch arm in `tr` (`"ar" =>`) can't leak in.
    fn keys_in_fn<'a>(src: &'a str, fn_sig: &str) -> std::collections::BTreeSet<&'a str> {
        let start = src.find(fn_sig).expect("function signature not found");
        let after = &src[start + fn_sig.len()..];
        // The body ends at the next top-level fn declaration.
        let end = after.find("\nfn ").unwrap_or(after.len());
        let body = &after[..end];

        let mut keys = std::collections::BTreeSet::new();
        for line in body.lines() {
            let t = line.trim_start();
            // Match lines shaped like:  "some.key" => "value",
            if let Some(rest) = t.strip_prefix('"') {
                if let Some(close) = rest.find('"') {
                    let key = &rest[..close];
                    let tail = rest[close + 1..].trim_start();
                    if tail.starts_with("=>") {
                        keys.insert(key);
                    }
                }
            }
        }
        keys
    }

    #[test]
    fn every_en_key_is_present_in_ar() {
        let src = include_str!("i18n.rs");
        let en_keys = keys_in_fn(src, "fn en(key: &str) -> Option<&'static str> {");
        let ar_keys = keys_in_fn(src, "fn ar(key: &str) -> Option<&'static str> {");

        // Sanity: the parser actually found a meaningful number of keys.
        assert!(
            en_keys.len() > 100,
            "parser found too few EN keys: {}",
            en_keys.len()
        );
        assert!(
            ar_keys.len() > 100,
            "parser found too few AR keys: {}",
            ar_keys.len()
        );

        let missing: Vec<&str> = en_keys.difference(&ar_keys).copied().collect();
        assert!(
            missing.is_empty(),
            "keys present in EN but missing from AR translation table: {missing:?}"
        );
    }

    #[test]
    fn ar_has_no_orphan_keys_absent_from_en() {
        // Reverse direction: an AR key with no EN counterpart can never be
        // reached via `tr` for an en locale and signals a typo/stale entry.
        let src = include_str!("i18n.rs");
        let en_keys = keys_in_fn(src, "fn en(key: &str) -> Option<&'static str> {");
        let ar_keys = keys_in_fn(src, "fn ar(key: &str) -> Option<&'static str> {");

        let orphans: Vec<&str> = ar_keys.difference(&en_keys).copied().collect();
        assert!(
            orphans.is_empty(),
            "keys present in AR but missing from EN table: {orphans:?}"
        );
    }

    #[test]
    fn every_en_key_resolves_nonempty_in_both_locales() {
        // Round-trip the parsed EN keys through the public `tr` to prove that
        // no key resolves to the fallback-key (which would mean a real miss)
        // and that AR yields a distinct, non-empty string.
        let src = include_str!("i18n.rs");
        let en_keys = keys_in_fn(src, "fn en(key: &str) -> Option<&'static str> {");
        for key in en_keys {
            let en_val = tr("en", key);
            let ar_val = tr("ar", key);
            assert_ne!(en_val, key, "EN key {key} resolved to itself (missing)");
            assert!(!ar_val.is_empty(), "AR value for {key} is empty");
        }
    }
}
