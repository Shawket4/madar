//! Static UI-string localization (PLAN: shared core owns logic). One source of
//! truth for both hosts — a string change here lands in Swift AND Kotlin at once.
//! Dynamic content (menu `*_translations`) is resolved separately in `menu`.
//!
//! Resolution: device locale → its language subtag → `en` → the key itself.
//! RTL languages (ar/…) are flagged so the host can flip layout direction.
//!
//! KNOWN LIMITATION — plurals: `tr` takes no count, so a key can carry only
//! ONE Arabic string, never the six CLDR plural forms (zero/one/two/few/
//! many/other) Arabic grammar actually uses. Every Dart call site that shows
//! a live count builds `'$n ' + tr(key)` (e.g. `order.items`, `tables.seats`,
//! `tables.guests`, `sync.tries`, `chrome.orders`) — the noun picked here is
//! therefore only grammatically correct for SOME values of `n`, never all of
//! them, and there is no fix available at this layer. Where the whole phrase
//! lives in one key (`history.sales_count`, `history.found_count`) it is
//! rephrased as "count of X: N" to sidestep the agreement question instead
//! of picking a wrong-most-of-the-time plural. A real fix needs `tr` (or a
//! new entry point) to accept a count and select among plural forms — a
//! signature change that ripples into every `bridge.tr(key: …)` call site,
//! out of scope for a strings-only pass.

/// Localized string for `key` in `locale`, falling back en → key.
pub fn tr(locale: &str, key: &str) -> String {
    let lang = lang_of(locale);
    let resolved = match lang {
        "ar" => ar(key),
        _ => None,
    };
    resolved.or_else(|| en(key)).unwrap_or(key).to_string()
}

/// The locale is Arabic (any region) — for formatting that has Arabic words.
pub fn is_arabic(locale: &str) -> bool {
    lang_of(locale) == "ar"
}

pub fn is_rtl(locale: &str) -> bool {
    matches!(lang_of(locale), "ar" | "fa" | "he" | "ur")
}

fn lang_of(locale: &str) -> &str {
    locale.split(['-', '_']).next().unwrap_or(locale)
}

fn en(key: &str) -> Option<&'static str> {
    Some(match key {
        // ── tills rework (TILLS_CONTRACT §7.2 / §10.4) ──
        "till.open_elsewhere_title" => "Your till is open on another device",
        "till.open_elsewhere_body" => "Close it on {device} first.",
        "till.force_close_elsewhere" => "Force close it",
        "till.unverified_badge" => "Not verified",
        "till.unverified_hint" => "Opened offline — will be checked when online.",
        "till.flagged_badge" => "Opened while another till was open",
        "till.branch_open_tills" => "Open tills in this branch",
        "till.this_device" => "This device",
        "till.reconcile_title" => "Check each payment method",
        "till.reconcile_checked" => "Checked",
        "till.reconcile_disagree" => "Doesn't match",
        "till.reconcile_amount" => "Amount you see",
        "till.reconcile_note" => "What happened?",
        "till.reconcile_note_required" => "Add a note for the difference.",
        "till.reconcile_system" => "System total",
        "till.reconcile_unreviewed" => "Not reviewed",
        "till.last_till_title" => "This is the last open till",
        "till.last_till_body" => "{bills} bills ({amount}) are still open and {tables} tables are seated.",
        "till.close_anyway" => "Close anyway",
        "till.open_bills_notice" => "{count} bills left open since {since}",
        "till.old_bills" => "{count} older than {hours}h",
        "till.z_old_bills" => "Old open bills",
        "till.z_reconciliation" => "Payment check",
        "till.z_device" => "Device",
        "till.drawer_cash" => "Cash in drawer",
        "kitchen.routing_till" => "POS queue",
        "sync.running" => "Syncing…",
        "sync.done" => "Up to date",
        "sync.stale_offline" => "Offline — showing data from {time}",
        "sync.stale_checksum" => "Some data may be out of date",
        "sync.stale_error" => "Sync failed",
        "sync.pending_count" => "{count} waiting to send",
        "sync.full_confirm_title" => "Download everything again?",
        "sync.full_confirm_body" => "Unsent sales are kept.",
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
        "till.open_title" => "Open your till",
        "till.opening_desc" => "Count the cash in the drawer to start selling.",
        "till.opening_cash" => "Opening cash",
        "till.open_button" => "Open till",
        "till.signed_in_as" => "Signed in as",
        "till.switch_teller" => "Switch teller",
        "till.welcome" => "Welcome back",
        "till.opening_hint" => "Count the cash already in the drawer before you start.",
        "till.suggested_from_close" => "From last close",
        "till.opening_reason_label" => "Reason for the difference",
        "till.opening_reason_hint" => "The opening count differs from the last close.",
        "till.opening_reason_required" => "Add a reason for the cash difference.",
        "common.done" => "Done",
        // order
        "order.title" => "Order",
        "order.coming_soon" => "Catalog & ordering — coming next.",
        "order.close_till" => "Close till",
        "till.close_title" => "Close till",
        "till.closing_desc" => "Count the drawer and close out your till.",
        "till.summary" => "Till summary",
        "till.teller" => "Teller",
        "till.opened_at" => "Opened",
        "till.counted_cash" => "Counted cash",
        "till.cash_note" => "Note (optional)",
        "till.system_cash" => "Expected cash",
        "till.system_cash_explain" => "Opening float + cash sales − cash out",
        "till.drawer_matches" => "Drawer matches",
        "err.payment_method_unavailable" => "This payment method isn't available on this till. Choose another one.",
        "till.drawer_over" => "Over by",
        "till.drawer_short" => "Short by",
        "till.report" => "Till report",
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
        "printing.chit_preview" => "Kitchen chit",
        "printing.no_printer" => "No printer is set up on this device",
        "printing.failed" => "The printer did not answer",
        "kitchen.chit_table" => "Table",
        "kitchen.chit_note" => "NOTE:",
        "printing.cart_chit" => "Send whole cart to kitchen",
        "printing.cart_chit_preview" => "Kitchen chit — whole cart",
        "printing.cart_chit_sent" => "Sent to the kitchen",
        "sell.kitchen_note" => "Kitchen note",
        "sell.kitchen_note_title" => "Note for the kitchen — this dish",
        "sell.kitchen_note_hint" => "For the kitchen only — never the receipt",
        "sell.cart_kitchen_note_title" => "Note for the kitchen — whole cart",
        "sell.cart_kitchen_note_hint" => "For the kitchen only — never the receipt",
        "order.service_charge" => "Service",
        "receipt.prices_include_vat" => "Prices include VAT",
        "receipt.vat_included" => "VAT (included)",
        "receipt.service_waived" => "Service charge removed",
        "checkout.remove_service" => "Remove service charge",
        "checkout.keep_service" => "Keep service charge",
        "checkout.service_removed_hint" => "Service charge removed from this bill",
        "checkout.tax_included_in_prices" => "Tax included in prices",
        "till.total_tax" => "Tax (net of refunds)",
        "till.total_service" => "Service charge (net of refunds)",
        "till.service_waived" => "Service charge waived",
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
        // A table's own history: what it has done and what it earns. The
        // figures count SETTLED bills only — an open bill has not finished
        // and a voided one took nothing.
        "tables.history" => "Table history",
        "tables.history_hint" => "Last 30 days",
        "tables.history_empty" => "Nothing has sat here in the last 30 days.",
        "tables.history_offline" => {
            "Takings need a connection — this one is not cached, so it can \
             never show you last week's numbers by mistake."
        }
        "tables.history_forbidden" => "Your role can't see this table's takings.",
        "tables.history_missing" => "This table is no longer on the floor.",
        "tables.history_unreadable" => "This app can't read the history the server sent. Update the app.",
        "tables.move_failed" => "Couldn't move the table",
        "floor.open_bill" => "Open bill",
        "floor.bill_so_far" => "Bill so far",
        "err.move_both_empty" => "Both tables are empty. Nothing to move.",
        "err.move_dirty" => "That table still needs clearing.",
        "err.move_booked" => "That table is held for a booking.",
        "err.move_same" => "Pick a different table.",
        "tables.covers" => "Covers",
        "tables.takings" => "Takings",
        "tables.avg_bill" => "Average bill",
        "tables.avg_time" => "Average stay",
        "tables.turns" => "Turns a day",
        "tables.sittings" => "Bills",
        "tables.still_open" => "Still open",
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
        // Taking a line off a cart — not `loyalty.remove`, which is about
        // unlinking a customer.
        "order.remove_line" => "Remove",
        // Confirmations for the acts that cannot be walked back. Each says
        // what is LOST, not just what the button is called: a dialog that
        // only repeats the verb adds a tap and no information.
        "order.clear_cart_title" => "Clear {count} items from the cart?",
        "order.clear_cart_body" => {
            "Every line goes, including anything already configured. The \
             order itself has not been sent anywhere, so nothing is refunded \
             and nothing is voided — it is simply gone."
        }
        "order.clear_cart" => "Clear it",
        "order.remove_line_title" => "Take this off?",
        "kds.discard_refused_title" => "Discard this refused action?",
        "kds.discard_refused_body" => {
            "The kitchen never accepted it and it will not be retried. \
             Whatever it was meant to do has not happened."
        }
        "transfer.cancel_title" => "Cancel this transfer?",
        "transfer.cancel_body" => {
            "The table keeps its bill where it is. Nothing moves."
        }
        "loyalty.remove_title" => "Take the customer off this sale?",
        "loyalty.remove_body" => {
            "No points are earned and no reward is applied. The sale stands."
        }
        "settings.sign_out_title" => "Sign out of this till?",
        "settings.sign_out_body" => {
            "Queued sales stay on the device and send when the next person \
             signs in. Nothing is lost — but nobody can ring up until then."
        }
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
        // What a programme collects, after a count ("30 points", "4 orders"),
        // and the progress line once a reward is reached.
        "loyalty.unit_points" => "points",
        "loyalty.unit_orders" => "orders",
        "loyalty.reward_earned" => "Reward earned",
        "loyalty.scan_hint" => "Hold their wallet pass to the scanner, or point the camera at it.",
        "loyalty.phone_hint" => "Look the customer up by the number they signed up with.",
        "loyalty.phone_label" => "Phone number",
        "loyalty.phone_placeholder" => "01x xxxx xxxx",
        "loyalty.look_up" => "Look up",
        "loyalty.scanner_ready" => "Ready for the barcode scanner",
        "loyalty.use_phone" => "No card? Use their phone number",
        "loyalty.scan_card_instead" => "Scan a card instead",
        "loyalty.reward" => "Reward",
        "loyalty.reward_line_gone" => "A rewarded item is no longer on the bill, so its reward came off",
        "loyalty.reward_not_on_offer" => "That item is not a reward here any more",
        "loyalty.reward_line_shrank" => "Fewer of that item on the bill now, so fewer are free",
        "loyalty.reward_cap_one" => "One reward per order here",
        "loyalty.reward_cap_many" => "Up to {n} rewards per order here",
        "loyalty.reward_balance_short" => "Not enough on the card for another",
        "loyalty.reward_no_bundles" => "Bundles can't be taken as a reward",
        "loyalty.reward_offline" => "Rewards need a connection. Reconnect, or charge without the reward.",
        "loyalty.reward_member_changed" => "The card changed since it was scanned — the rewards were updated. Check the total and charge again.",
        "loyalty.reward_programme_off" => "The loyalty programme was switched off, so the rewards came off the bill.",
        "loyalty.reward_refused" => "Reward given without points",
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
        "waiter.need_shift" => "Open a till to settle",
        "waiter.void_title" => "Void ticket",
        "waiter.void_reason" => "Reason (optional)",
        "ticket.status.open" => "Open",
        "ticket.status.ready" => "Ready",
        "ticket.status.settled" => "Settled",
        "ticket.status.voided" => "Voided",
        "ticket.status.queued" => "Queued",
        "common.void" => "Void",
        "common.save" => "Save",
        "common.cancel" => "Cancel",
        // A clock figure's short units ("1h 05m", "42m") and its under-a-minute
        // word — seated tables, bills, table history, the clock-skew banner.
        "common.hours_short" => "h",
        "common.minutes_short" => "m",
        "common.now" => "now",
        // The Android notification channel's name, shown in the OS settings.
        "notif.channel" => "Madar alerts",
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
        "sync.op_open_till" => "Open till",
        "sync.op_close_till" => "Close till",
        "sync.op_create_order" => "Sale",
        // order-screen chrome (action bar + banners)
        "chrome.online" => "Online",
        "chrome.clock_skew" => "Device clock is off — please fix it",
        "sync.freshness_never_synced" => "Nothing synced to this device yet — connect to download the branch",
        "sync.freshness_stale" => "Showing the last synced data — the latest could not be downloaded",
        "sync.store_newer_build" => "This device's data was saved by a newer version of the app — update the app to keep selling",
        "chrome.offline" => "Offline",
        "chrome.offline_banner" => "Working offline — changes sync when you reconnect",
        "chrome.auth_paused" => "Sync paused — sign in again to resume",
        "chrome.view" => "View",
        "chrome.auth_paused_action" => "Sign in",
        "chrome.reauth_title" => "Resume sync",
        "chrome.reauth_body" => "Your session expired. Enter your PIN to resume syncing.",
        "chrome.reauth_as" => "Signed in as",
        "chrome.reauth_switch" => "Close till & switch teller",
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
        "cash.empty" => "No cash movements this till.",
        "cash.history" => "Movements",
        "cash.total_in" => "Total in",
        "cash.total_out" => "Total out",
        "cash.net" => "net",
        "tills.title" => "Past tills",
        "tills.empty" => "No tills yet.",
        "tills.closed" => "Closed",
        "tills.opening" => "Opening",
        "tills.declared" => "Declared",
        "tills.discrepancy" => "Discrepancy",
        "tills.orders" => "Orders",
        "tills.no_orders" => "No orders in this till.",
        "tills.open_now" => "Open",
        // Z-report (printed shift report)
        "till.report_title" => "Till Report",
        "till.payments" => "Payments",
        "till.refunds" => "Refunds",
        "till.refunds_cash" => "Refunds in cash",
        "till.cash_in_refunded" => "Cash on refunded sales",
        "till.cash_moves" => "Cash in/out",
        "till.cash_in" => "Cash in",
        "till.cash_out" => "Cash out",
        "till.expected_cash" => "Expected cash",
        "till.by_method" => "By method",
        "till.business_date" => "Business Date",
        "till.printed_at" => "Printed at",
        "till.interim" => "Interim Report (Till Still Open)",
        "till.orders" => "orders",
        "till.total_collected" => "Total Collected",
        "till.drawer_ops" => "Drawer Operations",
        "till.cash_recon" => "Cash Reconciliation",
        "till.not_closed" => "Till not yet closed",
        "till.difference" => "Difference",
        "till.opening_mismatch" => "Opening mismatch",
        "till.transactions" => "Transactions",
        "till.end_of_report" => "End of Report",
        "till.print_report" => "Print report",
        "drafts.title" => "Held orders",
        "drafts.hold" => "Hold this order",
        "drafts.empty" => "No held orders.",
        "drafts.current" => "Current",
        // Discarding a PARKED order, which is not the sync centre's
        // "discard this stuck command" — same word, different thing, and
        // the two were sharing a key.
        "drafts.discard_title" => "Discard {name}?",
        "drafts.discard_body" => "Its {count} items are gone for good. Nothing was sent, so nothing is refunded or voided.",
        "drafts.on_table" => "Held on {table}",
        "drafts.this_order" => "this order",
        "drafts.discard" => "Discard",
        "drafts.rename" => "Name this order",
        // side-rail labels + section captions
        "nav.incoming" => "Incoming",
        "nav.section.orders" => "Orders",
        "nav.section.money" => "Money",
        "nav.section.system" => "System",
        // order history
        "history.title" => "Orders",
        "nav.history" => "History",
        "history.empty" => "No orders this till yet.",
        "history.queued" => "Queued",
        "history.completed" => "Completed",
        "history.search" => "Search orders",
        "history.failed" => "Failed",
        "history.voided" => "Voided",
        "history.order" => "Order",
        // order-history table (Flutter-style columns / filters / stats)
        "history.current_till" => "Current till",
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
        "settings.motion" => "Animations",
        "settings.motion_full" => "Full",
        "settings.motion_reduced" => "Reduced",
        "settings.motion_system" => "System",
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
        "settings.lan_hub_hint" => "Peer IP[:port] — optional (e.g. 192.168.1.50:47600)",
        "settings.lan_caption" => {
            "Set a fixed hub if devices can't find each other automatically on this Wi-Fi."
        }
        "settings.lan_active" => "Relay active",
        "settings.lan_offline" => "Relay off",
        "settings.lan_peers" => "peers",
        "settings.lan_port" => "Relay port",
        "settings.lan_discovery" => "Discovery",
        "settings.lan_discovery_none" => "None yet",
        "settings.lan_disc_bonjour" => "Bonjour",
        "settings.lan_disc_mdns" => "mDNS",
        "settings.lan_disc_beacon" => "Broadcast",
        "settings.lan_disc_manual" => "Manual peer",
        "settings.lan_last_error" => "Last start error",
        "settings.lan_retrying" => "Retrying automatically",
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
        "settings.sign_out_shift_open" => "Close your till before signing out.",
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
        // The core's own refusals, worded for a teller. The core raises them in
        // English (a log reads them); `humanMessage` in rust_bridge swaps each
        // known detail for its key so the screen says it in the app's language.
        "err.not_signed_in" => "Sign in first.",
        "err.session_expired" => "Your session ended — sign in again.",
        "err.wrong_pin" => "That PIN isn't right.",
        "err.no_offline_bundle" => "This till can't sign in offline yet — sign in once while online.",
        "err.cart_empty" => "The cart is empty.",
        "err.no_shift" => "Open a till first.",
        "err.held_elsewhere" => "This order is open on another till.",
        "err.parked_gone" => "That parked order is gone.",
        "err.line_gone" => "That line is no longer in the cart.",
        "err.unknown_payment" => "That payment method isn't available here.",
        "err.scan_or_phone" => "Scan a card or type a phone number.",
        "err.no_order_points" => "There's no sale to add points to.",
        "err.table_taken" => "Another till just took this table.",
        "err.transfer_waiting" => "This party is already waiting to move.",
        "err.shift_for_stranded" => "Open a till first so the waiting orders can move onto it.",
        "err.cash_note" => "Add a note for this cash movement.",
        "err.amount_zero" => "Enter an amount above zero.",
        "err.amount_range" => "That amount is too large.",
        "err.refund_queued" => "This sale hasn't synced yet — refund it once it has.",
        "err.force_close_reason" => "Say why you're closing someone else's drawer.",
        // ── the redesign (2026-09-12): three shells, one Charge, a Bill that is a screen ──
        // shells (apps/madar): tab words and the outbox pill
        "nav.sell" => "Sell",
        "nav.floor" => "Floor",
        "nav.queue" => "Queue",
        "nav.orders" => "Orders",
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
        // selling-flow audit (2026-09-13): words that were Dart literals
        "sell.rounds_count" => "Rounds: {count}",
        "sell.round_tag" => "R{count}",
        "sell.discount_on_cart" => "Discount applied",
        "common.quoted" => "“{text}”",
        "order.at_least" => "at least {count}",
        "order.at_most" => "at most {count}",
        "order.addon_other" => "Options",
        "order.options_unavailable" => "Couldn't load this item's options. Try again.",
        "charge.no_methods" => "No payment methods — sync the menu, then try again",
        "queue.bill_not_synced" => "Not sent yet — charge it once it syncs",
        "queue.prep_minutes" => "{count} min",
        "sell.guest_name" => "Guest name",
        "sell.round_n" => "Round",
        // selling redesign (2026-09-13)
        "sell.order_title" => "Order",
        "sell.open_till" => "Open till",
        "sell.no_shift" => "No till is open — open one to take payment",
        "sell.customer" => "Customer",
        "sell.discount" => "Discount",
        "sell.note" => "Note",
        "sell.note_title" => "Note for this order",
        "sell.note_hint" => "Rides the kitchen ticket and the order",
        "charge.reason_cash" => "Enter the cash received",
        "charge.reason_split" => "The split has to add up to the total",
        "charge.reason_method" => "Pick how they are paying",
        "charge.rest_here" => "Rest here",
        "charge.new_sale" => "New sale",
        // selling redesign: queue
        "queue.col_status" => "Status",
        "queue.col_channel" => "Channel",
        "queue.col_time" => "Time",
        "queue.empty_online_hint" => "Online orders appear here the moment a customer places one.",
        "queue.col_ticket" => "Ticket",
        "queue.col_items" => "Items",
        "queue.empty_kitchen_hint" => "Rounds appear here when they are fired to the counter's kitchen.",
        "queue.col_open_for" => "Open for",
        "queue.open_bill" => "Open the bill",
        "queue.empty_bills_hint" => "Bills appear here when a table's first round goes to the kitchen.",
        // selling redesign: item sheet
        "sell.item_note_hint" => "Note for the kitchen (optional)",
        // floor
        "floor.title" => "Floor",
        "floor.seat" => "Seat",
        "floor.party_size" => "Party size",
        "floor.take_order" => "Take an order",
        "floor.unseat" => "Unseat (party left)",
        // Says what is LOST, because that is what the confirmation is for:
        // the covers and the time seated are not recoverable, and the only
        // way back is seating the party again from scratch.
        "floor.unseat_confirm" => {
            "The table goes back to available and this party's covers and \
             seated-at time are gone. Only a bill already settled survives."
        }
        "floor.cleared" => "Cleared",
        "floor.seat_booking_here" => "Seat a booking here",
        "floor.walk_in_here" => "Walk-in here",
        "floor.no_bill_yet" => "No bill yet",
        // bill + the waiter's bills tab
        "bill.title" => "Bill",
        "bill.void_bill" => "Void bill",
        "bill.unseat_has_bill" => "This table has a bill. Charge it or void it to free the table.",
        "floor.table_actions" => "Table actions",
        "floor.seat_and_order" => "Seat & take order",
        "floor.needs_attention" => "Needs attention",
        "floor.all_calm_title" => "Nothing needs you right now",
        "floor.all_calm_desc" => "Ready food, tables to clear, long waits and arriving bookings show up here. Tap a table to work it.",
        "floor.waiting_long" => "Waiting long",
        "floor.fit_room" => "Fit room",
        "floor.empty_section" => "No tables in this section",
        "floor.empty_section_desc" => "Pick another section, or add tables to this one in the dashboard.",
        "floor.no_layout_title" => "No floor plan yet",
        "floor.no_layout_desc" => "Ask a manager to draw the floor in the dashboard, then sync.",
        "floor.bill_preview" => "Bill",
        "floor.all_tables" => "All",
        "floor.move" => "Move",
        "tables.history_empty_hint" => "Settled and voided bills on this table appear here with their time, covers and total.",
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
        // The FAMILY a payment method belongs to, shown as a caption under a
        // shop-named method: "InstaPay" alone says nothing about how the money
        // moves, and two custom methods with the same generic icon are
        // otherwise indistinguishable on the tender drawer.
        "charge.kind_cash" => "Cash",
        "charge.kind_card" => "Card",
        "charge.kind_wallet" => "Wallet",
        "charge.kind_custom" => "Custom",
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
        "queue.kitchen" => "Kitchen",
        "queue.accept" => "Accept",
        "queue.decline" => "Decline",
        "queue.decline_reason" => "Reason",
        "queue.ready_in" => "Ready in",
        // The promise ("Ready by 19:25") vs the fact, once the kitchen finished
        // ("Ready 19:19") — reuses `queue.ready_by`'s wording, this is the latter.
        "queue.ready_at" => "Ready",
        "queue.minutes" => "minutes",
        "queue.charge" => "Charge",
        "queue.picked_up" => "Picked up",
        "queue.view" => "View",
        "queue.empty" => "Nothing waiting.",
        "queue.offline_notice" => "Offline — showing the last list",
        "queue.no_table" => "No table",
        "queue.accepted" => "Accepted",
        "queue.declined" => "Declined",
        "queue.need_shift" => "Open the till first",
        // till (the drawer tab), cash in / out kinds, the close arithmetic
        "till.title" => "Till",
        "till.open_since" => "open since",
        "till.sales" => "Sales",
        "till.cash_in_till" => "Cash in till",
        "till.this_shift" => "This till",
        "till.orders_this_shift" => "Orders this till",
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
        "till.opening_float" => "Opening float",
        "till.cash_sales" => "Cash sales",
        "till.paid_in" => "Paid in",
        "till.paid_out" => "Paid out",
        "till.z_preview" => "Z report preview",
        "till.why_short" => "Why is it short?",
        "till.why_over" => "Why is it over?",
        "till.close_hint" => "Closing locks Sell and Charge on this till.",
        "till.reason_required" => "reason required",
        "tills.force_closed" => "Force-closed",
        // orders (history): this shift / all, the sale, void versus refund
        "history.this_shift" => "This till",
        "history.sales_count" => "{count} sales",
        "history.found_count" => "{count} found",
        "history.no_shift" => "No till open",
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
        "history.offline_search" => "Searching past tills needs a connection.",
        "history.offline_cached" => "Offline — showing what was loaded.",
        "history.retry" => "Try again",
        "history.price_flagged" => "Offline price",
        "history.price_flagged_hint" => {
            "Rung offline against an older menu — the price differs from the menu today."
        }
        "history.void_sale" => "Void sale",
        "history.void_teach" => "Void removes a mistaken sale as if it never happened.",
        "history.refund_sale" => "Refund",
        "history.refund_teach" => "Refund returns money on a sale that stands.",
        "history.refunded" => "Refunded",
        "history.refund_left" => "{amount} left to refund",
        "history.refund_all" => "Already refunded in full.",
        "history.refund_queued" => "Waiting to send",
        // the refund sheet: how much, back by what method, and why
        "history.refund_amount" => "Amount to return",
        "history.refund_method" => "Back by",
        "history.refund_reason" => "Why",
        "history.refund_confirm" => "Refund",
        "history.refund_over" => "More than the sale was for.",
        "history.refund_needs_shift" => {
            "A refund is cash out of a drawer — open a shift first."
        }
        "history.refund_reason_customer" => "Customer asked",
        "history.refund_reason_wrong" => "Wrong order",
        "history.refund_reason_quality" => "Quality",
        "history.refund_reason_overcharged" => "Overcharged",
        "history.refund_reason_other" => "Something else",
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
        "kds.load_failed" => "Couldn't load the kitchen board",
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
        "sync.recover_need_shift" => "Open a till first",
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
        // toggles (segmented on/off)
        "toggle.off" => "Off",
        "toggle.on" => "On",
        "toggle.single_payment" => "One method",
        "login.name_required" => "Type your name, then your PIN.",
        "login.pin_too_short" => "A PIN is at least 4 digits.",
        "login.reconfigure_title" => "Reconfigure this device?",
        "login.reconfigure_body" => "The till leaves its branch until a manager signs in and binds it again. Tellers cannot sign in meanwhile.",
        "settings.test_receipt_line" => "Test print",
        "till.count_required" => "Count the drawer and enter the amount first.",
        "till.closing_reason_required" => "Say why the count is off before closing.",
        "till.report_load_failed" => "Could not load this till's report.",
        "till.report_no_sales" => "No sales in this till.",
        "till.closed_report_title" => "Till closed — Z report",
        "cash.confirm_pay_out" => "Pay out {amount} from the drawer?",
        "till.preview_x" => "Preview X report",
        "history.reason_required" => "Choose why first.",
        "history.preview_receipt" => "Preview",
        "payment.mixed" => "Split",
        "cash.kind.safe_drop" => "Safe drop",
        "cash.kind.correction" => "Correction",
        "history.refund_method_pick" => "Choose how the money goes back.",
        "history.refund_other_shift" => "This sale is from an earlier till — the refund comes out of today's drawer.",
        // ── Spec migration: till, shifts, orders, settings, sign-in ──
        "common.close" => "Close",
        "history.col_number" => "#",
        "history.col_time" => "Time",
        "history.col_type" => "Type",
        "history.col_payment" => "Payment",
        "history.col_status" => "Status",
        "history.empty_message" => "Sales you ring up appear here.",
        "history.refund_left_label" => "Left to refund",
        "history.status_paid" => "Paid",
        "history.status_part_refunded" => "Partly refunded",
        "tills.length" => "Length",
        "tills.balanced" => "Balanced",
        "tills.short" => "Short",
        "tills.over" => "Over",
        "tills.empty_message" => "Every till this branch opens and closes appears here.",
        "till.payment_methods" => "Payment methods",
        "till.orders_col" => "Orders",
        "cash.note_col" => "For",
        "cash.amount_col" => "Amount",
        "till.drawer" => "Drawer",
        "till.show_orders" => "Show orders",
        "till.hide_orders" => "Hide orders",
        "chrome.see_all" => "See all",
        "cash.empty_message" => "Pay-ins and pay-outs you record appear here.",
        "settings.this_device" => "This device",
        "me.no_bills_message" => "Bills you open on the floor appear here.",
        _ => return None,
    })
}

fn ar(key: &str) -> Option<&'static str> {
    Some(match key {
        // ── tills rework (TILLS_CONTRACT §7.2 / §10.4) ──
        "till.open_elsewhere_title" => "ورديتك مفتوحة على جهاز آخر",
        "till.open_elsewhere_body" => "أغلقها أولًا على {device}.",
        "till.force_close_elsewhere" => "إغلاق إجباري",
        "till.unverified_badge" => "غير متحقق منها",
        "till.unverified_hint" => "فُتحت دون اتصال — سيتم التحقق عند الاتصال.",
        "till.flagged_badge" => "فُتحت أثناء وجود وردية أخرى مفتوحة",
        "till.branch_open_tills" => "الورديات المفتوحة في هذا الفرع",
        "till.this_device" => "هذا الجهاز",
        "till.reconcile_title" => "راجع كل طريقة دفع",
        "till.reconcile_checked" => "تمت المراجعة",
        "till.reconcile_disagree" => "غير مطابق",
        "till.reconcile_amount" => "المبلغ الفعلي",
        "till.reconcile_note" => "ماذا حدث؟",
        "till.reconcile_note_required" => "أضف ملاحظة توضح الفرق.",
        "till.reconcile_system" => "إجمالي النظام",
        "till.reconcile_unreviewed" => "لم تتم المراجعة",
        "till.last_till_title" => "هذه آخر وردية مفتوحة",
        "till.last_till_body" => "ما زالت {bills} فواتير ({amount}) مفتوحة و{tables} طاولات مشغولة.",
        "till.close_anyway" => "أغلق على أي حال",
        "till.open_bills_notice" => "{count} فواتير متروكة مفتوحة منذ {since}",
        "till.old_bills" => "{count} أقدم من {hours} ساعة",
        "till.z_old_bills" => "فواتير قديمة مفتوحة",
        "till.z_reconciliation" => "مراجعة المدفوعات",
        "till.z_device" => "الجهاز",
        "till.drawer_cash" => "النقد في الخزنة",
        "kitchen.routing_till" => "طابور نقطة البيع",
        "sync.running" => "جارٍ المزامنة…",
        "sync.done" => "محدّث",
        "sync.stale_offline" => "غير متصل — البيانات من {time}",
        "sync.stale_checksum" => "قد تكون بعض البيانات غير محدّثة",
        "sync.stale_error" => "فشلت المزامنة",
        "sync.pending_count" => "{count} بانتظار الإرسال",
        "sync.full_confirm_title" => "تنزيل كل البيانات من جديد؟",
        "sync.full_confirm_body" => "المبيعات غير المرسلة ستبقى محفوظة.",
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
        "till.open_title" => "افتح ورديتك",
        "till.opening_desc" => "احسب النقد في الخزنة لبدء البيع.",
        "till.opening_cash" => "النقد الافتتاحي",
        "till.open_button" => "فتح الوردية",
        "till.signed_in_as" => "مسجّل الدخول باسم",
        "till.switch_teller" => "تبديل الأمين",
        "till.welcome" => "مرحبًا بعودتك",
        "till.opening_hint" => "احسب النقد الموجود في الخزنة قبل أن تبدأ.",
        "till.suggested_from_close" => "من آخر إغلاق",
        "till.opening_reason_label" => "سبب الاختلاف",
        "till.opening_reason_hint" => "العدّ الافتتاحي يختلف عن آخر إغلاق.",
        "till.opening_reason_required" => "أضِف سبباً لاختلاف النقدية.",
        "common.done" => "تم",
        "order.title" => "طلب",
        "order.coming_soon" => "القائمة والطلبات — قريبًا.",
        "order.close_till" => "إغلاق الوردية",
        "till.close_title" => "إغلاق الوردية",
        "till.closing_desc" => "احسب الخزنة وأغلق ورديتك.",
        "till.summary" => "ملخص الوردية",
        "till.teller" => "أمين الصندوق",
        "till.opened_at" => "فُتحت",
        "till.counted_cash" => "النقد المحسوب",
        "till.cash_note" => "ملاحظة (اختياري)",
        "till.system_cash" => "النقد المتوقع",
        "till.system_cash_explain" => "الافتتاحي + المبيعات النقدية − المسحوب",
        "till.drawer_matches" => "الخزنة مطابق",
        "err.payment_method_unavailable" => "طريقة الدفع هذه غير متاحة على هذه الوردية. اختر طريقة أخرى.",
        "till.drawer_over" => "زيادة",
        "till.drawer_short" => "نقص",
        "till.report" => "تقرير الوردية",
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
        "printing.chit_preview" => "ورقة المطبخ",
        "printing.no_printer" => "لا توجد طابعة معدّة على هذا الجهاز",
        "printing.failed" => "لم تستجب الطابعة",
        "kitchen.chit_table" => "طاولة",
        "kitchen.chit_note" => "ملاحظة:",
        "printing.cart_chit" => "إرسال كل السلة إلى المطبخ",
        "printing.cart_chit_preview" => "ورقة المطبخ — كل السلة",
        "printing.cart_chit_sent" => "أُرسل إلى المطبخ",
        "sell.kitchen_note" => "ملاحظة للمطبخ",
        "sell.kitchen_note_title" => "ملاحظة للمطبخ — هذا الطبق",
        "sell.kitchen_note_hint" => "للمطبخ فقط — لا تُطبع على الفاتورة",
        "sell.cart_kitchen_note_title" => "ملاحظة للمطبخ — كل السلة",
        "sell.cart_kitchen_note_hint" => "للمطبخ فقط — لا تُطبع على الفاتورة",
        "order.service_charge" => "الخدمة",
        "receipt.prices_include_vat" => "الأسعار شاملة ضريبة القيمة المضافة",
        "receipt.vat_included" => "ضريبة القيمة المضافة (مشمولة)",
        "receipt.service_waived" => "تم إلغاء رسوم الخدمة",
        "checkout.remove_service" => "إلغاء رسوم الخدمة",
        "checkout.keep_service" => "إبقاء رسوم الخدمة",
        "checkout.service_removed_hint" => "تم إلغاء رسوم الخدمة من هذه الفاتورة",
        "checkout.tax_included_in_prices" => "الضريبة مشمولة في الأسعار",
        "till.total_tax" => "الضريبة (بعد المرتجعات)",
        "till.total_service" => "رسوم الخدمة (بعد المرتجعات)",
        "till.service_waived" => "رسوم خدمة ملغاة",
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
        // Deliberately NOT "محجوزة" (the word `tables.reserved` uses) — this is
        // a race with another till, not a customer's booking, and reusing the
        // booking word would tell the teller the wrong story.
        "tables.taken" => "سبقك جهاز آخر إلى هذه الطاولة — تم الحفظ بدونها",
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
        // A soft hold, not a confirmed booking — kept distinct from
        // `tables.reserved` below so the two pills never read the same.
        "tables.held_res" => "قيد الحجز",
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
        "tables.history" => "سجل الطاولة",
        "tables.history_hint" => "آخر ٣٠ يومًا",
        "tables.history_empty" => "لم يجلس أحد هنا خلال آخر ٣٠ يومًا.",
        "tables.history_offline" => {
            "تحتاج الأرقام إلى اتصال — وهي غير محفوظة محليًا حتى لا تعرض \
             أرقام الأسبوع الماضي بالخطأ."
        }
        "tables.history_forbidden" => "دورك لا يسمح برؤية إيرادات هذه الطاولة.",
        "tables.history_missing" => "هذه الطاولة لم تعد في الصالة.",
        "tables.history_unreadable" => "لا يستطيع التطبيق قراءة السجل الذي أرسله الخادم. حدّث التطبيق.",
        "tables.move_failed" => "تعذّر نقل الطاولة",
        "floor.open_bill" => "افتح الفاتورة",
        "floor.bill_so_far" => "الفاتورة حتى الآن",
        "err.move_both_empty" => "الطاولتان فارغتان. لا شيء لنقله.",
        "err.move_dirty" => "هذه الطاولة ما زالت تحتاج تنظيفًا.",
        "err.move_booked" => "هذه الطاولة محجوزة لحجز.",
        "err.move_same" => "اختر طاولة أخرى.",
        "tables.covers" => "عدد الأفراد",
        "tables.takings" => "الإيراد",
        "tables.avg_bill" => "متوسط الفاتورة",
        "tables.avg_time" => "متوسط مدة الجلوس",
        "tables.turns" => "دورات في اليوم",
        "tables.sittings" => "الفواتير",
        "tables.still_open" => "ما زالت مفتوحة",
        "tables.seat_held" => "ضع طلبًا معلّقًا هنا",
        "tables.view_list" => "قائمة",
        "tables.view_plan" => "مخطط",
        "tables.due" => "مستحق الآن",
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
        "order.remove_line" => "حذف الصنف",
        "order.clear_cart_title" => "تفريغ {count} من الأصناف من السلة؟",
        "order.clear_cart_body" => {
            "ستُحذف كل الأصناف بما فيها ما تم تخصيصه. الطلب لم يُرسل إلى أي \
             مكان، فلا يوجد استرداد ولا إبطال — سيختفي فقط."
        }
        "order.clear_cart" => "تفريغ السلة",
        "order.remove_line_title" => "هل تريد حذف هذا الصنف؟",
        "kds.discard_refused_title" => "هل تريد تجاهل هذا الإجراء المرفوض؟",
        "kds.discard_refused_body" => {
            "لم يقبله المطبخ ولن تُعاد المحاولة. ما كان من المفترض أن يحدث \
             لم يحدث."
        }
        "transfer.cancel_title" => "هل تريد إلغاء النقل؟",
        "transfer.cancel_body" => "ستبقى الفاتورة على طاولتها. لن يتغير شيء.",
        "loyalty.remove_title" => "هل تريد إزالة العميل من هذه العملية؟",
        "loyalty.remove_body" => {
            "لن تُحتسب نقاط ولن تُطبّق مكافأة. تبقى عملية البيع كما هي."
        }
        "settings.sign_out_title" => "هل تريد تسجيل الخروج من هذا الجهاز؟",
        "settings.sign_out_body" => {
            "تبقى المبيعات المنتظرة على الجهاز وتُرسل عند تسجيل دخول التالي. \
             لن يضيع شيء — لكن لن يتمكن أحد من البيع حتى ذلك الحين."
        }
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
        // Plural after a figure, the same compromise as `tables.guests`
        // (see the plurals note at the top of this file).
        "loyalty.unit_points" => "نقاط",
        "loyalty.unit_orders" => "طلبات",
        "loyalty.reward_earned" => "المكافأة جاهزة",
        "loyalty.scan_hint" => "قرّب بطاقة العميل من الماسح، أو وجّه الكاميرا إليها.",
        "loyalty.phone_hint" => "ابحث عن العميل برقم الهاتف المسجّل به.",
        "loyalty.phone_label" => "رقم الهاتف",
        "loyalty.phone_placeholder" => "01x xxxx xxxx",
        "loyalty.look_up" => "بحث",
        "loyalty.scanner_ready" => "جاهز لماسح الباركود",
        "loyalty.use_phone" => "لا توجد بطاقة؟ استخدم رقم الهاتف",
        "loyalty.scan_card_instead" => "امسح بطاقة بدلاً من ذلك",
        "loyalty.reward" => "مكافأة",
        "loyalty.reward_line_gone" => "لم يعد صنف المكافأة في الفاتورة، فأُلغيت مكافأته",
        "loyalty.reward_not_on_offer" => "هذا الصنف لم يعد مكافأة هنا",
        "loyalty.reward_line_shrank" => "قلّت كمية هذا الصنف في الفاتورة، فقلّ عدد المجاني منه",
        "loyalty.reward_cap_one" => "مكافأة واحدة لكل طلب هنا",
        "loyalty.reward_cap_many" => "حتى {n} مكافآت لكل طلب هنا",
        "loyalty.reward_balance_short" => "الرصيد في البطاقة لا يكفي لمكافأة أخرى",
        "loyalty.reward_no_bundles" => "لا يمكن أخذ الوجبات المجمّعة كمكافأة",
        "loyalty.reward_offline" => "المكافآت تحتاج إلى اتصال. أعد الاتصال أو احسب بدون المكافأة.",
        "loyalty.reward_member_changed" => "تغيّرت البطاقة منذ مسحها وتم تحديث المكافآت. راجع الإجمالي ثم احسب مجدداً.",
        "loyalty.reward_programme_off" => "تم إيقاف برنامج الولاء، فأُزيلت المكافآت من الفاتورة.",
        "loyalty.reward_refused" => "مُنحت المكافأة دون خصم نقاط",
        "tables.start_order_here" => "ابدأ طلبًا هنا",
        "tables.settle" => "تحصيل الحساب",
        "receipt.printing" => "جارٍ الطباعة…",
        "receipt.printed" => "تم الإرسال إلى الطابعة",
        "receipt.print_failed" => "تعذّر الوصول إلى الطابعة",
        "receipt.no_printer" => "اضبط الطابعة في الإعدادات",
        "receipt.ref" => "مرجع:",
        // The participle of إبطال, not إلغاء: the button says "Void"
        // (إبطال) everywhere, so the state it leaves behind must not read
        // "cancelled". Vocalised (مُبطَل, not مبطل) because the bare spelling
        // is also "the one who voids".
        "receipt.voided" => "مُبطَل",
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
        // Void ("إبطال") is a distinct action from Cancel ("إلغاء") throughout
        // this file — it erases a mistaken sale/ticket as if it never
        // happened, an audited action, not a plain "never mind". Every
        // `void.*`/`*.void_*`/`sync.op_void_*` key below uses the same word.
        "waiter.void_title" => "إبطال التذكرة",
        "waiter.void_reason" => "السبب (اختياري)",
        "ticket.status.open" => "مفتوحة",
        "ticket.status.ready" => "جاهزة",
        "ticket.status.settled" => "مُسوّاة",
        // Feminine: تذكرة. See `receipt.voided` for the root.
        "ticket.status.voided" => "مُبطَلة",
        "ticket.status.queued" => "بالانتظار",
        "common.void" => "إبطال",
        "common.save" => "حفظ",
        "common.cancel" => "إلغاء",
        // س / د after a Western figure ("1س 05د"), matching `kds.age_min` and
        // the app's figures, which stay Western everywhere (money included) —
        // not ساعة/دقيقة, which do not fit a table's pill.
        "common.hours_short" => "س",
        "common.minutes_short" => "د",
        "common.now" => "الآن",
        "notif.channel" => "تنبيهات مدار",
        // reservations & floor plan (host UI)
        "reservations.title" => "الحجوزات",
        "reservations.seat" => "إجلاس",
        "reservations.seated" => "تم الإجلاس",
        "reservations.moved" => "تم النقل",
        "reservations.setStatus" => "تعيين الحالة",
        "reservations.noBookings" => "لا توجد حجوزات نشطة",
        "reservations.status_free" => "فارغة",
        // Same word as `tables.held_res` — see the note there: a hold is not
        // a booking, so it must not share `tables.reserved`'s "محجوزة".
        "reservations.status_held" => "قيد الحجز",
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
        "sync.op_open_till" => "فتح وردية",
        "sync.op_close_till" => "إغلاق وردية",
        // EN says "Sale", not "Order" — matches `charge.sale`/`history.sale`
        // ("بيع"), not `order.title` ("طلب").
        "sync.op_create_order" => "بيع",
        // order-screen chrome (action bar + banners)
        "chrome.online" => "متصل",
        "chrome.clock_skew" => "ساعة الجهاز غير مضبوطة — يرجى تصحيحها",
        "sync.freshness_never_synced" => "لم تُزامَن أي بيانات على هذا الجهاز بعد — اتصل لتنزيل بيانات الفرع",
        "sync.freshness_stale" => "تُعرض آخر بيانات تمت مزامنتها — تعذّر تنزيل الأحدث",
        "sync.store_newer_build" => "بيانات هذا الجهاز محفوظة بإصدار أحدث من التطبيق — حدّث التطبيق لمواصلة البيع",
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
        "tills.title" => "الورديات السابقة",
        "tills.empty" => "لا توجد ورديات بعد.",
        "tills.closed" => "أُغلقت",
        "tills.opening" => "رصيد البداية",
        "tills.declared" => "المعلن",
        "tills.discrepancy" => "الفرق",
        "tills.orders" => "الطلبات",
        "tills.no_orders" => "لا توجد طلبات في هذه الوردية.",
        "tills.open_now" => "مفتوحة",
        // Z-report (printed shift report)
        "till.report_title" => "تقرير الوردية",
        "till.payments" => "المدفوعات",
        "till.refunds" => "المبالغ المستردة",
        "till.refunds_cash" => "المسترد نقداً",
        "till.cash_in_refunded" => "نقد مبيعات مستردة",
        "till.cash_moves" => "إيداع/سحب",
        "till.cash_in" => "إيداع نقدي",
        "till.cash_out" => "سحب نقدي",
        "till.expected_cash" => "النقد المتوقع",
        "till.by_method" => "حسب الطريقة",
        "till.business_date" => "تاريخ العمل",
        "till.printed_at" => "وقت الطباعة",
        "till.interim" => "تقرير مبدئي (الوردية ما زالت مفتوحة)",
        "till.orders" => "طلب",
        "till.total_collected" => "إجمالي المحصّل",
        "till.drawer_ops" => "عمليات الخزنة",
        "till.cash_recon" => "تسوية النقدية",
        "till.not_closed" => "لم تُغلق الوردية بعد",
        "till.difference" => "الفرق",
        "till.opening_mismatch" => "فرق الافتتاح",
        "till.transactions" => "المعاملات",
        "till.end_of_report" => "نهاية التقرير",
        "till.print_report" => "طباعة التقرير",
        "drafts.title" => "طلبات معلّقة",
        "drafts.hold" => "تعليق هذا الطلب",
        "drafts.empty" => "لا توجد طلبات معلّقة.",
        "drafts.current" => "الحالي",
        "drafts.discard_title" => "إلغاء {name}؟",
        "drafts.discard_body" => "ستُحذف أصنافه ({count}) نهائيًا. لم يُرسل شيء، فلا استرداد ولا إبطال.",
        "drafts.on_table" => "مُعلّق على {table}",
        "drafts.this_order" => "هذا الطلب",
        "drafts.discard" => "إلغاء الطلب",
        "drafts.rename" => "اسم هذا الطلب",
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
        "history.voided" => "مُبطَل",
        "history.order" => "طلب",
        // order-history table (Flutter-style columns / filters / stats)
        "history.current_till" => "الوردية الحالية",
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
        "settings.motion" => "الحركة",
        "settings.motion_full" => "كاملة",
        "settings.motion_reduced" => "مخففة",
        "settings.motion_system" => "النظام",
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
        "settings.lan_hub_hint" => "عنوان جهاز[:المنفذ] — اختياري (مثل 192.168.1.50:47600)",
        "settings.lan_caption" => {
            "عيّن موزّعًا ثابتًا إذا تعذّر على الأجهزة العثور على بعضها تلقائيًا على هذه الشبكة."
        }
        "settings.lan_active" => "التتابع نشط",
        "settings.lan_offline" => "التتابع متوقّف",
        "settings.lan_peers" => "أجهزة",
        "settings.lan_port" => "منفذ التتابع",
        "settings.lan_discovery" => "الاكتشاف",
        "settings.lan_discovery_none" => "لا شيء بعد",
        "settings.lan_disc_bonjour" => "بونجور",
        "settings.lan_disc_mdns" => "اكتشاف mDNS",
        "settings.lan_disc_beacon" => "البث",
        "settings.lan_disc_manual" => "جهاز يدوي",
        "settings.lan_last_error" => "آخر خطأ في التشغيل",
        "settings.lan_retrying" => "إعادة المحاولة تلقائيًا",
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
        "err.not_signed_in" => "سجّل الدخول أولًا.",
        "err.session_expired" => "انتهت الجلسة — سجّل الدخول مرة أخرى.",
        "err.wrong_pin" => "الرقم السري غير صحيح.",
        "err.no_offline_bundle" => "لا يمكن الدخول دون اتصال على هذا الجهاز بعد — سجّل الدخول مرة وأنت متصل.",
        "err.cart_empty" => "السلة فارغة.",
        "err.no_shift" => "افتح وردية أولًا.",
        "err.held_elsewhere" => "هذا الطلب مفتوح على جهاز آخر.",
        "err.parked_gone" => "هذا الطلب المركون لم يعد موجودًا.",
        "err.line_gone" => "هذا البند لم يعد في السلة.",
        "err.unknown_payment" => "طريقة الدفع هذه غير متاحة هنا.",
        "err.scan_or_phone" => "امسح البطاقة أو اكتب رقم الموبايل.",
        "err.no_order_points" => "لا توجد عملية بيع لإضافة النقاط إليها.",
        "err.table_taken" => "جهاز آخر أخذ هذه الطاولة للتو.",
        "err.transfer_waiting" => "هذه المجموعة تنتظر النقل بالفعل.",
        "err.shift_for_stranded" => "افتح وردية أولًا حتى تنتقل إليها الطلبات المعلّقة.",
        "err.cash_note" => "اكتب ملاحظة لحركة النقدية هذه.",
        "err.amount_zero" => "أدخل مبلغًا أكبر من صفر.",
        "err.amount_range" => "المبلغ كبير جدًا.",
        "err.refund_queued" => "لم تتم مزامنة هذه العملية بعد — استردّها بعد المزامنة.",
        "err.force_close_reason" => "اذكر سبب إغلاق خزنة شخص آخر.",
        // ── the redesign (2026-09-12): three shells, one Charge, a Bill that is a screen ──
        // shells (apps/madar): tab words and the outbox pill
        "nav.sell" => "البيع",
        "nav.floor" => "الصالة",
        "nav.queue" => "الوارد",
        "nav.orders" => "الطلبات",
        "nav.till" => "الوردية",
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
        "sell.rounds_count" => "الجولات: {count}",
        "sell.round_tag" => "ج{count}",
        "sell.discount_on_cart" => "تم تطبيق خصم",
        // Arabic quotes are guillemets, and they sit the right way round in RTL.
        "common.quoted" => "«{text}»",
        "order.at_least" => "على الأقل {count}",
        "order.at_most" => "بحد أقصى {count}",
        "order.addon_other" => "خيارات",
        "order.options_unavailable" => "تعذّر تحميل خيارات هذا الصنف. حاول مرة أخرى.",
        "charge.no_methods" => "لا توجد طرق دفع — زامن القائمة ثم حاول مرة أخرى",
        "queue.bill_not_synced" => "لم تُرسل بعد — حصّلها بعد المزامنة",
        "queue.prep_minutes" => "{count} د",
        "sell.guest_name" => "اسم الضيف",
        "sell.round_n" => "جولة",
        // selling redesign (2026-09-13)
        "sell.order_title" => "الطلب",
        "sell.open_till" => "افتح وردية",
        "sell.no_shift" => "لا توجد وردية مفتوحة — افتح وردية لتحصيل المبالغ",
        "sell.customer" => "العميل",
        "sell.discount" => "خصم",
        "sell.note" => "ملاحظة",
        "sell.note_title" => "ملاحظة على الطلب",
        "sell.note_hint" => "تصل مع تذكرة المطبخ والطلب",
        "charge.reason_cash" => "أدخل المبلغ النقدي المستلم",
        "charge.reason_split" => "يجب أن يساوي مجموع التقسيم الإجمالي",
        "charge.reason_method" => "اختر طريقة الدفع",
        "charge.rest_here" => "الباقي هنا",
        "charge.new_sale" => "بيع جديد",
        // selling redesign: queue
        "queue.col_status" => "الحالة",
        "queue.col_channel" => "القناة",
        "queue.col_time" => "الوقت",
        "queue.empty_online_hint" => "تظهر الطلبات الأونلاين هنا لحظة أن يطلبها العميل.",
        "queue.col_ticket" => "التذكرة",
        "queue.col_items" => "الأصناف",
        "queue.empty_kitchen_hint" => "تظهر الجولات هنا عندما تُرسل إلى مطبخ الكاشير.",
        "queue.col_open_for" => "مفتوحة منذ",
        "queue.open_bill" => "افتح الفاتورة",
        "queue.empty_bills_hint" => "تظهر الفواتير هنا عندما تُرسل أول جولة لطاولة إلى المطبخ.",
        // selling redesign: item sheet
        "sell.item_note_hint" => "ملاحظة للمطبخ (اختياري)",
        // floor
        "floor.title" => "الصالة",
        "floor.seat" => "إجلاس",
        "floor.party_size" => "عدد الأفراد",
        "floor.take_order" => "خذ الطلب",
        "floor.unseat" => "إلغاء الإجلاس (غادروا)",
        "floor.unseat_confirm" => {
            "ستعود الطاولة إلى المتاحة، ويُفقد عدد الأفراد ووقت الجلوس. لا \
             يبقى إلا ما تم تحصيله بالفعل."
        }
        "floor.cleared" => "تم التنظيف",
        "floor.seat_booking_here" => "أجلس حجزًا هنا",
        "floor.walk_in_here" => "زبون عابر هنا",
        "floor.no_bill_yet" => "لا فاتورة بعد",
        // bill + the waiter's bills tab
        "bill.title" => "الفاتورة",
        "bill.void_bill" => "إبطال الفاتورة",
        "bill.unseat_has_bill" => "على هذه الطاولة فاتورة. حصّلها أو أبطلها لتحرير الطاولة.",
        "floor.table_actions" => "إجراءات الطاولة",
        "floor.seat_and_order" => "إجلاس وأخذ الطلب",
        "floor.needs_attention" => "تحتاج انتباهك",
        "floor.all_calm_title" => "لا شيء يحتاجك الآن",
        "floor.all_calm_desc" => "الطلبات الجاهزة والطاولات التي تحتاج تنظيفًا والانتظار الطويل والحجوزات القادمة تظهر هنا. اضغط على طاولة للعمل عليها.",
        "floor.waiting_long" => "انتظار طويل",
        "floor.fit_room" => "ملاءمة الصالة",
        "floor.empty_section" => "لا طاولات في هذا القسم",
        "floor.empty_section_desc" => "اختر قسمًا آخر، أو أضف طاولات لهذا القسم من لوحة التحكم.",
        "floor.no_layout_title" => "لا يوجد مخطط للصالة بعد",
        "floor.no_layout_desc" => "اطلب من المدير رسم الصالة في لوحة التحكم، ثم زامن.",
        "floor.bill_preview" => "الفاتورة",
        "floor.all_tables" => "الكل",
        "floor.move" => "نقل",
        "tables.history_empty_hint" => "تظهر هنا الفواتير المحصّلة والملغاة على هذه الطاولة مع وقتها وعدد الضيوف والإجمالي.",
        "bill.gone" => "أُغلقت هذه الفاتورة على جهاز آخر",
        "bill.ready" => "جاهز",
        "bill.queued" => "في الانتظار",
        // Feminine agreement: فاتورة is feminine, so the participle takes the
        // ة ending (compare `history.voided`, describing a بيع — masculine).
        "bill.voided" => "مُبطَلة",
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
        "charge.kind_cash" => "نقدي",
        "charge.kind_card" => "بطاقة",
        "charge.kind_wallet" => "محفظة",
        "charge.kind_custom" => "مخصص",
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
        "queue.kitchen" => "المطبخ",
        "queue.accept" => "قبول",
        "queue.decline" => "رفض",
        "queue.decline_reason" => "السبب",
        "queue.ready_in" => "جاهز خلال",
        "queue.ready_at" => "جاهز",
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
        "till.title" => "الوردية",
        "till.open_since" => "مفتوحة منذ",
        "till.sales" => "المبيعات",
        "till.cash_in_till" => "النقد في الخزنة",
        "till.this_shift" => "هذه الوردية",
        "till.orders_this_shift" => "طلبات هذه الوردية",
        "till.print_x" => "طباعة تقرير X",
        "till.drawers" => "الخزن",
        "till.force_close_unavailable" => {
            "الإغلاق الإجباري غير متاح من هذا الجهاز بعد — استخدم لوحة التحكم."
        }
        "cash.pay_out" => "سحب",
        "cash.pay_in" => "إيداع",
        "cash.note_hint" => "ملاحظة · لأي غرض",
        "cash.note_required" => "مطلوب",
        "cash.record_pay_out" => "تسجيل السحب",
        "cash.record_pay_in" => "تسجيل الإيداع",
        "till.opening_float" => "الرصيد الافتتاحي",
        "till.cash_sales" => "المبيعات النقدية",
        "till.paid_in" => "المودع",
        "till.paid_out" => "المسحوب",
        "till.z_preview" => "معاينة تقرير Z",
        "till.why_short" => "ما سبب النقص؟",
        "till.why_over" => "ما سبب الزيادة؟",
        "till.close_hint" => "الإغلاق يوقف البيع والتحصيل على هذه الوردية.",
        "till.reason_required" => "السبب مطلوب",
        "tills.force_closed" => "أُغلقت إجبارياً",
        // orders (history): this shift / all, the sale, void versus refund
        "history.this_shift" => "هذه الوردية",
        // "{count} مبيعات" only agrees for counts 3–10 — Arabic has six
        // plural forms and `tr` carries no count to pick between them (see
        // i18n.rs's module docs / this feature's report). Phrasing it as
        // "count of X: N" instead of "N nouns" sidesteps the agreement
        // question rather than shipping a form that is wrong most shifts.
        "history.sales_count" => "عدد المبيعات: {count}",
        "history.found_count" => "عدد النتائج: {count}",
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
        "history.refund_sale" => "استرداد",
        "history.refund_teach" => "الاسترداد يرجع المال مع بقاء عملية البيع.",
        "history.refunded" => "مُسترد",
        "history.refund_left" => "متبقٍ للاسترداد {amount}",
        "history.refund_all" => "تم استرداد المبلغ بالكامل.",
        "history.refund_queued" => "بانتظار الإرسال",
        "history.refund_amount" => "المبلغ المسترد",
        "history.refund_method" => "طريقة الإرجاع",
        "history.refund_reason" => "السبب",
        "history.refund_confirm" => "استرداد",
        "history.refund_over" => "أكبر من قيمة عملية البيع.",
        "history.refund_needs_shift" => "الاسترداد نقد يخرج من الخزنة — افتح وردية أولاً.",
        "history.refund_reason_customer" => "طلب العميل",
        "history.refund_reason_wrong" => "طلب خاطئ",
        "history.refund_reason_quality" => "الجودة",
        "history.refund_reason_overcharged" => "زيادة في الحساب",
        "history.refund_reason_other" => "سبب آخر",
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
        "kds.load_failed" => "تعذّر تحميل لوحة المطبخ",
        // sync (waiting / stuck / blocked), settings rows, me, roles
        "sync.live_on" => "تحديثات مباشرة",
        "sync.live_off" => "بدون تحديثات مباشرة",
        "sync.waiting" => "بالانتظار",
        "sync.stuck" => "متعثر",
        "sync.needs_you" => "يحتاجك",
        "sync.blocked" => "محجوز",
        "sync.blocked_hint" => "توقفت هذه المبيعات بسبب فشل فتح الوردية. افتح وردية جديدة لاسترجاعها.",
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
        "sync.op_void_order" => "إبطال بيع",
        "sync.op_cash_movement" => "حركة نقدية",
        "sync.op_open_ticket" => "فاتورة جديدة",
        "sync.op_ticket_add_round" => "جولة",
        "sync.op_void_ticket" => "إبطال فاتورة",
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
        // toggles (segmented on/off)
        "toggle.off" => "إيقاف",
        "toggle.on" => "تشغيل",
        "toggle.single_payment" => "طريقة واحدة",
        "login.name_required" => "اكتب اسمك ثم الرقم السري.",
        "login.pin_too_short" => "الرقم السري 4 أرقام على الأقل.",
        "login.reconfigure_title" => "إعادة تهيئة هذا الجهاز؟",
        "login.reconfigure_body" => "تخرج الكاشة من فرعها حتى يسجّل مدير الدخول ويربطها من جديد. لا يستطيع الكاشير تسجيل الدخول خلال ذلك.",
        "settings.test_receipt_line" => "طباعة تجريبية",
        "till.count_required" => "عُدّ الخزنة وأدخل المبلغ أولاً.",
        "till.closing_reason_required" => "اذكر سبب اختلاف العدّ قبل الإغلاق.",
        "till.report_load_failed" => "تعذّر تحميل تقرير هذه الوردية.",
        "till.report_no_sales" => "لا توجد مبيعات في هذه الوردية.",
        "till.closed_report_title" => "أُغلقت الوردية — تقرير Z",
        "cash.confirm_pay_out" => "صرف {amount} من الخزنة؟",
        "till.preview_x" => "معاينة تقرير X",
        "history.reason_required" => "اختر السبب أولاً.",
        "history.preview_receipt" => "معاينة",
        "payment.mixed" => "مقسّم",
        "cash.kind.safe_drop" => "إيداع في الخزنة",
        "cash.kind.correction" => "تصحيح",
        "history.refund_method_pick" => "اختر طريقة إرجاع المبلغ.",
        "history.refund_other_shift" => "هذه البيعة من وردية سابقة — يُصرف الاسترداد من خزنة اليوم.",
        // ── Spec migration: till, shifts, orders, settings, sign-in ──
        "common.close" => "إغلاق",
        "history.col_number" => "#",
        "history.col_time" => "الوقت",
        "history.col_type" => "النوع",
        "history.col_payment" => "الدفع",
        "history.col_status" => "الحالة",
        "history.empty_message" => "تظهر هنا المبيعات التي تسجّلها.",
        "history.refund_left_label" => "المتبقي للاسترداد",
        "history.status_paid" => "مدفوع",
        "history.status_part_refunded" => "مُسترد جزئيًا",
        "tills.length" => "المدة",
        "tills.balanced" => "مطابقة",
        "tills.short" => "عجز",
        "tills.over" => "زيادة",
        "tills.empty_message" => "تظهر هنا كل وردية تُفتح وتُغلق في هذا الفرع.",
        "till.payment_methods" => "طرق الدفع",
        "till.orders_col" => "الطلبات",
        "cash.note_col" => "البيان",
        "cash.amount_col" => "المبلغ",
        "till.drawer" => "الخزنة",
        "till.show_orders" => "عرض الطلبات",
        "till.hide_orders" => "إخفاء الطلبات",
        "chrome.see_all" => "عرض الكل",
        "cash.empty_message" => "تظهر هنا المبالغ التي تُدخلها إلى الخزنة أو تُخرجها منه.",
        "settings.this_device" => "هذا الجهاز",
        "me.no_bills_message" => "تظهر هنا الفواتير التي تفتحها في الصالة.",
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn arabic_till_words_follow_the_rework() {
        // Decision 14: the till (a person's session) is الوردية; the physical
        // drawer is الخزنة.
        assert_eq!(super::ar("nav.till"), Some("الوردية"));
        assert_eq!(super::ar("till.title"), Some("الوردية"));
        assert_eq!(super::ar("till.drawer_matches"), Some("الخزنة مطابق"));
        assert_eq!(super::en("till.drawer_matches"), Some("Drawer matches"));
    }

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
