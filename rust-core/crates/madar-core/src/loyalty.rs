//! Loyalty: the view models the teller's scan screen renders, and the mapping
//! from the wire types into them.
//!
//! The UI holds no loyalty logic — it scans a barcode and renders what comes
//! back. In particular it never computes points: a sale's award is decided by
//! the server from the order's own totals when the order settles, so there is
//! nothing here for a till to get wrong or for a stale device to disagree about.
//!
//! Everything in this module is ONLINE-ONLY, deliberately. A balance is shared
//! state that any till in the org can move; an offline device cannot answer
//! "how many points does this person have" without risking a wrong number in
//! front of the customer, and a wrong balance is worse than a plain "reconnect
//! to look this up". Earning is unaffected — that rides in the order's outbox
//! payload and lands on replay.

use serde::{Deserialize, Serialize};

/// A member as the scan screen shows them.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyMemberView {
    pub id: String,
    pub name: String,
    pub phone: String,
    /// `points` (earned on spend) or `visits` (a stamp per order) — what this
    /// branch collects. One or the other, never both.
    pub mode: String,
    /// The live balance, in `mode`'s currency.
    pub balance: i64,
    /// The cheapest reward on offer here, in the same currency.
    pub next_reward_cost: i64,
    /// How many rewards are ALREADY earned and unclaimed.
    ///
    /// A card does not stop at full: six orders against a five-order reward is
    /// one earned and one towards the next. A teller needs the count, because a
    /// customer owed two rewards may claim both on one bill.
    pub rewards_ready: i64,
    /// Steps on the CURRENT card, after the earned ones are set aside.
    pub progress_to_next: i64,
    /// What the next reward still needs.
    pub points_to_next_reward: i64,
    /// The balance affords at least one reward on offer here.
    pub can_redeem: bool,
    /// Ready-made progress line ("3 / 5"), so the UI formats no numbers.
    pub progress_label: String,
    /// What to call the balance on screen — "points" or "orders".
    pub balance_label: String,
}

/// One reward the member could claim right now. Empty until they can.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyRewardView {
    pub menu_item_id: String,
    pub name: String,
    /// Menu price in minor units — what the reward is worth.
    pub price_minor: i64,
    /// `points` or `visits`.
    pub cost_currency: String,
    /// What it costs in that currency. Per item, so one catalogue holds
    /// "espresso, 5 orders" beside "cake, 10".
    pub cost_amount: i64,
    /// Ready-made ("5 orders"), so the UI formats no numbers.
    pub cost_label: String,
}

/// One line of the member's recent history, already phrased for display.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyLedgerView {
    /// "earn" | "redeem" | "adjust".
    pub kind: String,
    /// Signed, as stored: positive earns, negative redeems.
    pub points: i64,
    /// Already signed for display ("+13", "−100").
    pub points_label: String,
    /// `points` or `visits` — which balance this row moved.
    pub currency: String,
    pub branch_name: Option<String>,
    pub reward_name: Option<String>,
    pub created_at: String,
}

/// Everything the scan screen needs from one lookup.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyScanView {
    pub member: LoyaltyMemberView,
    pub rewards: Vec<LoyaltyRewardView>,
    pub recent: Vec<LoyaltyLedgerView>,
    /// The whole menu is claimable, not just `rewards`.
    ///
    /// When this is on the catalogue stops being the list of what MAY be
    /// claimed, so the till offers every line at `any_item_cost` rather than
    /// only the lines it can find in `rewards`.
    pub any_item: bool,
    /// What any line costs in that mode. Meaningless unless `any_item`.
    pub any_item_cost: i64,
    /// The shop's ceiling on reward ITEMS per order; `None` = no ceiling.
    pub max_rewards_per_order: Option<i64>,
}

/// What came of pressing "add points" on a sale.
///
/// The three outcomes a teller has to be able to tell apart are decided HERE,
/// from what the server said, and phrased here too. "Added", "already
/// collected" and "queued" are different facts about the customer's card, and a
/// till that guessed between them would eventually claim to have added points
/// it did not add.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyAwardOutcome {
    /// The member's standing after the call. `None` only when the press was
    /// queued: there is no balance yet, and inventing one is a lie the customer
    /// can read off the screen.
    pub member: Option<LoyaltyMemberView>,
    /// The till was offline (or the round trip failed) and the press is queued.
    pub queued: bool,
    /// This sale had ALREADY earned. The endpoint is idempotent per order, so a
    /// second press is safe — but the honest answer is "already collected", not
    /// a second "added".
    pub already_collected: bool,
    /// What THIS press added. Zero for an already-collected sale, and for a sale
    /// too small to reach one point.
    pub points_awarded: i64,
    /// The headline for the teller, already localized.
    pub headline: String,
    /// The line under it — where the customer now stands, or why there is no
    /// balance to show. Already localized and already filled in.
    pub detail: String,
}

/// The outcome of a press the server answered.
pub fn award_outcome(locale: &str, r: &madar_api::models::AwardResult) -> LoyaltyAwardOutcome {
    let member = member_view(&r.member, locale);
    let points = r.points_awarded as i64;
    let headline = if r.already_awarded {
        crate::i18n::tr(locale, "loyalty.already_collected")
    } else if points == 0 {
        // The sale is linked to the card either way — the server records who it
        // earned for even at zero — so this is "no points", not "no".
        crate::i18n::tr(locale, "loyalty.no_points")
    } else {
        crate::i18n::tr(locale, "loyalty.points_added")
    };
    let detail = format!(
        "{} — {} {} · {}",
        member.name, member.balance, member.balance_label, member.progress_label
    );
    LoyaltyAwardOutcome {
        member: Some(member),
        queued: false,
        already_collected: r.already_awarded,
        points_awarded: points,
        headline,
        detail,
    }
}

/// The outcome of a press this till could not deliver.
pub fn award_queued(locale: &str) -> LoyaltyAwardOutcome {
    LoyaltyAwardOutcome {
        member: None,
        queued: true,
        already_collected: false,
        points_awarded: 0,
        headline: crate::i18n::tr(locale, "loyalty.points_queued"),
        detail: crate::i18n::tr(locale, "loyalty.queued_hint"),
    }
}

/// How long after a sale its points may still be claimed.
///
/// Kept in lock-step with the server's `loyalty::award::AWARD_WINDOW_HOURS`. The
/// client copy exists so the button can hide itself and a queued op can be
/// refused before it is even enqueued; the SERVER's copy is the one that
/// decides, because a till's clock and a till's build are both things a customer
/// should not have to depend on.
pub const AWARD_WINDOW_HOURS: i64 = 24;

/// Is this sale still inside its award window, as of `now`?
///
/// Both arguments are RFC3339. An unparseable timestamp closes the window rather
/// than opening it: a button that should not be there is a worse failure than a
/// button that is missing, because the first one takes points from a customer
/// and tells them it worked.
pub fn award_window_open(order_created_at: &str, now: &str) -> bool {
    let (Ok(created), Ok(now)) = (
        chrono::DateTime::parse_from_rfc3339(order_created_at),
        chrono::DateTime::parse_from_rfc3339(now),
    ) else {
        return false;
    };
    let age = now.signed_duration_since(created);
    age >= chrono::Duration::zero() && age <= chrono::Duration::hours(AWARD_WINDOW_HOURS)
}

/// The outbox payload for a queued award (op_type `"award_loyalty_points"`).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AwardCommand {
    pub request: madar_api::models::AwardRequest,
}

/// What a string arriving from a scanner, a camera or a keyboard actually is.
///
/// The UI captures bytes — camera frames through the platform's decoder, USB
/// keystrokes through the OS text path — because those are platform I/O that
/// Rust cannot reach without re-implementing CameraX/AVFoundation and shipping
/// every frame across the bridge. But deciding *what a captured string means* is
/// logic, and it lives here so all three input paths agree.
///
/// This is also what makes a cheap USB imager work. Many wedge scanners type
/// their payload and never send Enter; the sheet can hand every keystroke to
/// [`classify_scan_input`] and fire the moment the buffer becomes a whole token,
/// with no per-device configuration and no guessing in Dart.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyScanInput {
    /// `token` — a complete member token, ready to look up.
    /// `phone`  — a plausible phone number, ready to look up.
    /// `partial` — not yet either; keep collecting keystrokes.
    pub kind: String,
    /// The cleaned value to send. Empty when `kind` is `partial`.
    pub value: String,
}

impl LoyaltyScanInput {
    fn partial() -> Self {
        Self {
            kind: "partial".into(),
            value: String::new(),
        }
    }
    fn token(v: String) -> Self {
        Self {
            kind: "token".into(),
            value: v,
        }
    }
    fn phone(v: String) -> Self {
        Self {
            kind: "phone".into(),
            value: v,
        }
    }
    pub fn is_ready(&self) -> bool {
        self.kind != "partial"
    }
}

/// A member token is `M` + 22 base64url characters — the shape the server
/// mints (madar-shared's `madar_ids::member`). A half-typed buffer is never
/// mistaken for a whole card.
#[cfg(test)]
const TOKEN_LEN: usize = madar_ids::member::TOKEN_LEN;

/// Classify a captured string. Never panics and never allocates on the hot
/// path's common answer (a partial buffer).
pub fn classify_scan_input(raw: &str) -> LoyaltyScanInput {
    let s = raw.trim();
    if s.is_empty() {
        return LoyaltyScanInput::partial();
    }

    // A card: exact length, the `M` sentinel, and a base64url tail.
    if madar_ids::member::is_member_token(s) {
        return LoyaltyScanInput::token(s.to_string());
    }

    // A phone: digits once the punctuation people type is removed — Arabic
    // numerals too. It leaves here in the ONE canonical form (`crate::phone`),
    // the form the server keys members and customers by, so `0100…`, `+20 100…`
    // and `٠١٠٠…` all look the same person up.
    let folded = crate::phone::digits(s);
    let only_phone_chars = s.chars().all(|c| {
        c.is_ascii_digit()
            || matches!(c, '+' | ' ' | '-' | '(' | ')' | '\u{0660}'..='\u{0669}' | '\u{06F0}'..='\u{06F9}')
    });
    if only_phone_chars && (10..=15).contains(&folded.len()) {
        if let Some(canonical) = crate::phone::canonical(s) {
            return LoyaltyScanInput::phone(canonical);
        }
    }

    LoyaltyScanInput::partial()
}

/// "30 / 100", or the earned line once the threshold is reached, in `locale`.
pub fn progress_label(balance: i64, threshold: i64, locale: &str) -> String {
    if threshold > 0 && balance >= threshold {
        crate::i18n::tr(locale, "loyalty.reward_earned")
    } else {
        format!("{balance} / {threshold}")
    }
}

/// A signed points figure for a history row. Uses a real minus sign, not a
/// hyphen, because these sit in a column of numbers.
pub fn points_label(points: i64) -> String {
    if points >= 0 {
        format!("+{points}")
    } else {
        format!("−{}", points.abs())
    }
}

/// What a program calls what it collects, in the customer's words.
///
/// "orders", not "visits" — the customer counts the things they bought, and that
/// is the word the counter says back to them.
pub fn balance_label(mode: &str, locale: &str) -> String {
    crate::i18n::tr(locale, balance_label_key(mode))
}

/// The i18n key behind [`balance_label`] — `loyalty.unit_orders` for a visits
/// programme, `loyalty.unit_points` otherwise. Hosts that re-word on a language
/// switch resolve this key themselves instead of keeping the finished word.
pub fn balance_label_key(mode: &str) -> &'static str {
    match mode {
        "visits" => "loyalty.unit_orders",
        _ => "loyalty.unit_points",
    }
}

/// The branch's programme, as the TILL needs it — three facts out of the
/// dashboard's forty.
///
/// Everything else on `LoyaltySettings` decides what the SERVER does when a
/// sale settles (the earn rate, the cap, the clawback rule). None of it is the
/// till's to apply, and mirroring it here would only give a stale device a
/// second opinion about a number the server already computed.
///
/// That includes per-item stamps (`stamp_per_line_item` and the shop's list of
/// collecting items, added 2026-09). It was worth writing down why the till
/// gets neither, because it looks at first like something the device ought to
/// know: the count now depends on the CART, which the till is holding.
///
/// It does not need to. An award is a request, not a calculation — the till
/// sends who, and the server answers with what the sale was worth, reading the
/// order's own lines out of its own tables. Offline that request is queued and
/// answered on drain, off the same rows, so an offline till and the one beside
/// it reach the same number without the offline one ever computing it. Nothing
/// on this screen previews a stamp count before the server replies, so there is
/// no figure here that could disagree.
///
/// Mirroring it would buy nothing and cost the one thing that matters: a device
/// whose catalogue was a day stale would quietly promise a different number
/// from the one the customer's card is about to receive. `covered_minor` is
/// mirrored (and pinned by `loyalty_reward_vectors.json`) because a REDEMPTION
/// changes what is owed on a screen the customer is reading before any server
/// sees it. Earning changes nothing until the server says so.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyProgrammeView {
    /// Is a programme running here at all?
    ///
    /// `false` means every loyalty control stays off the screen. A till that
    /// offers *Member ›* in a shop with no programme sends the teller looking
    /// for a card that cannot exist, and answers them with a lookup failure.
    pub enabled: bool,
    /// `points` (earned on spend) or `visits` (a stamp an order) — what the
    /// card collects, and so what the screen calls a balance BEFORE anyone has
    /// been scanned. Until now the mode was known only from a member, which is
    /// exactly too late to label the control that finds one.
    pub mode: String,
    /// What the shop calls it ("Rue Rewards"), in the till's language.
    pub program_name: String,
    /// The customer's word for what it collects — "points" / "orders".
    pub balance_label: String,
}

/// The programme as the synced settings row carries it (`loyalty`: enabled,
/// mode, program_name, program_name_ar) or a legacy fill stored whole. `None`
/// (no programme at the branch, nothing known yet) is the wire default:
/// disabled.
pub(crate) fn settings_from_value(v: Option<&serde_json::Value>) -> madar_api::models::LoyaltySettings {
    let mut s = madar_api::models::LoyaltySettings::default();
    let Some(v) = v.filter(|v| v.is_object()) else { return s };
    if let Some(e) = v.get("enabled").and_then(serde_json::Value::as_bool) {
        s.enabled = e;
    }
    if let Some(m) = v.get("mode").and_then(serde_json::Value::as_str) {
        s.mode = m.to_string();
    }
    if let Some(n) = v.get("program_name").and_then(serde_json::Value::as_str) {
        s.program_name = n.to_string();
    }
    s.program_name_ar = Some(v.get("program_name_ar").and_then(serde_json::Value::as_str).map(str::to_string));
    s
}

pub fn programme_view(
    s: &madar_api::models::LoyaltySettings,
    locale: &str,
) -> LoyaltyProgrammeView {
    LoyaltyProgrammeView {
        enabled: s.enabled,
        mode: s.mode.clone(),
        program_name: crate::menu::pick_lang(
            &s.program_name,
            s.program_name_ar
                .clone()
                .flatten()
                .unwrap_or_default()
                .as_str(),
            locale,
        ),
        balance_label: balance_label(&s.mode, locale),
    }
}

pub fn member_view(m: &madar_api::models::MemberView, locale: &str) -> LoyaltyMemberView {
    let balance = m.balance as i64;
    let target = m.next_reward_cost as i64;
    LoyaltyMemberView {
        id: m.id.to_string(),
        name: m.name.clone(),
        phone: m.phone.clone(),
        mode: m.mode.clone(),
        balance,
        next_reward_cost: target,
        rewards_ready: m.rewards_ready as i64,
        progress_to_next: m.progress_to_next as i64,
        points_to_next_reward: m.points_to_next_reward as i64,
        can_redeem: m.can_redeem,
        progress_label: progress_label(balance, target, locale),
        balance_label: balance_label(&m.mode, locale),
    }
}

pub fn scan_view(s: &madar_api::models::ScanResult, locale: &str) -> LoyaltyScanView {
    LoyaltyScanView {
        member: member_view(&s.member, locale),
        rewards: s
            .rewards
            .iter()
            .map(|r| LoyaltyRewardView {
                menu_item_id: r.menu_item_id.to_string(),
                name: r.name.clone(),
                price_minor: r.base_price as i64,
                cost_currency: r.cost_currency.clone(),
                cost_amount: r.cost_amount as i64,
                cost_label: format!(
                    "{} {}",
                    r.cost_amount,
                    balance_label(&r.cost_currency, locale)
                ),
            })
            .collect(),
        any_item: s.any_item,
        any_item_cost: s.any_item_cost as i64,
        max_rewards_per_order: s.max_rewards_per_order.flatten().map(i64::from),
        recent: s
            .recent
            .iter()
            .map(|e| LoyaltyLedgerView {
                kind: e.kind.clone(),
                points: e.points as i64,
                points_label: points_label(e.points as i64),
                currency: e.currency.clone(),
                branch_name: e.branch_name.clone().flatten(),
                reward_name: e.reward_name.clone().flatten(),
                created_at: e.created_at.to_rfc3339(),
            })
            .collect(),
    }
}

// ── Rewards on a basket ──────────────────────────────────────────────────────
//
// Which lines a member's balance may cover, how many units, what that costs and
// what it takes off the bill — decided HERE, from the same rules the server's
// `loyalty::redeem::plan` applies, so the Charge screen never offers what the
// server would refuse and never charges for what it covered.

/// A line a reward could cover, as the reward rules see it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewardLineInput {
    /// For the rewards section's row.
    pub name: String,
    /// Position in the cart (the server indexes a cart's lines by position).
    pub cart_index: Option<u32>,
    /// `open_ticket_items.id` for a bill line (a settle names lines by id).
    pub ticket_line_id: Option<String>,
    /// `None` for a line with no menu item — never coverable.
    pub menu_item_id: Option<String>,
    pub qty: i32,
    /// The line as charged (modifiers included, before any reward).
    pub line_total_minor: i64,
    /// The line is a STAFF DRINK: the pool already gives it away, so it can
    /// never be taken as a reward too (the server refuses the pair with a 400).
    pub is_staff_drink: bool,
}

/// A reward applied to one line: which line (its position in the list the
/// board was built from) and how many of its units.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewardPick {
    pub line: u32,
    pub units: i32,
}

/// One line on the board.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewardLineState {
    pub line: u32,
    /// The balance's catalogue lists this line (or any item is claimable).
    pub claimable: bool,
    /// What one unit costs, in the member's currency. 0 when not claimable.
    pub unit_cost: i64,
    /// Units currently covered.
    pub units: i32,
    /// Tapping would cover one more unit.
    pub can_add: bool,
    /// Why it cannot, in the till's language; `None` when it can (or when the
    /// line is simply fully covered, which the tap then clears).
    pub blocked_reason: Option<String>,
    /// Minor units the covered units take off this line.
    pub covered_minor: i64,
    /// Ready-made cost, e.g. "5 orders".
    pub cost_label: String,
}

/// Everything the rewards section renders, and the picks to send.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewardBoardView {
    pub lines: Vec<RewardLineState>,
    /// The picks that survive the rules — what Charge must send. Differs from
    /// what was asked when a line shrank, vanished, or the balance/cap moved.
    pub picks: Vec<RewardPick>,
    /// Balance spent by `picks`.
    pub cost: i64,
    pub balance_after: i64,
    /// Reward ITEMS claimed (what the per-order cap counts).
    pub units_claimed: i32,
    /// Minor units taken off the bill before any discount.
    pub covered_minor: i64,
    /// The asked picks did not all survive; says why, in the till's language.
    pub adjusted_reason: Option<String>,
}

/// A cart's lines, in the order the server indexes them.
pub fn reward_lines_from_cart(lines: &[crate::cart::CartLineView]) -> Vec<RewardLineInput> {
    lines
        .iter()
        .enumerate()
        .map(|(i, l)| RewardLineInput {
            name: l.name.clone(),
            cart_index: Some(i as u32),
            ticket_line_id: None,
            menu_item_id: Some(l.item_id.clone()).filter(|s| !s.is_empty()),
            qty: l.qty as i32,
            line_total_minor: l.line_total_minor,
            is_staff_drink: l.staff_drink.is_some(),
        })
        .collect()
}

/// A bill's lines a reward could name: live (not voided), synced (an id the
/// server can resolve), and carrying a menu item. Rounds added later simply
/// appear; a line voided after the tap drops out and its reward with it.
pub fn reward_lines_from_ticket(lines: &[crate::tickets::TicketLineView]) -> Vec<RewardLineInput> {
    lines
        .iter()
        .filter(|l| !l.voided && !l.id.is_empty())
        .map(|l| RewardLineInput {
            name: l.name.clone(),
            cart_index: None,
            ticket_line_id: Some(l.id.clone()),
            is_staff_drink: false,
            menu_item_id: l.menu_item_id.clone(),
            qty: l.qty,
            line_total_minor: l.line_total_minor,
        })
        .collect()
}

/// The asked redemptions as picks into `lines` — by cart position or by
/// ticket line id. A redemption naming nothing in `lines` becomes a pick past
/// the end, which the board drops and names.
pub fn picks_from_redemptions(
    lines: &[RewardLineInput],
    asked: &[crate::checkout::CheckoutRedemption],
) -> Vec<RewardPick> {
    asked
        .iter()
        .map(|r| {
            let found = match &r.ticket_line_id {
                Some(id) => lines
                    .iter()
                    .position(|l| l.ticket_line_id.as_deref() == Some(id)),
                None => lines
                    .iter()
                    .position(|l| l.cart_index == Some(r.item_index)),
            };
            RewardPick {
                line: found.unwrap_or(lines.len()) as u32,
                units: r.units,
            }
        })
        .collect()
}

/// The board's picks in the shape a checkout or settle sends.
pub fn redemptions_from_picks(
    lines: &[RewardLineInput],
    picks: &[RewardPick],
) -> Vec<crate::checkout::CheckoutRedemption> {
    picks
        .iter()
        .filter_map(|p| {
            let l = lines.get(p.line as usize)?;
            Some(crate::checkout::CheckoutRedemption {
                item_index: l.cart_index.unwrap_or(0),
                ticket_line_id: l.ticket_line_id.clone(),
                units: p.units,
            })
        })
        .collect()
}

/// A line as madar-shared's redemption planner reads it.
fn plan_line(line: &RewardLineInput) -> madar_loyalty::Line {
    madar_loyalty::Line {
        menu_item_id: line.menu_item_id.clone(),
        quantity: i64::from(line.qty),
        is_staff_drink: line.is_staff_drink,
    }
}

/// This balance's programme, as the planner reads it.
fn programme_of(scan: &LoyaltyScanView) -> madar_loyalty::Programme {
    madar_loyalty::Programme {
        rewards: scan
            .rewards
            .iter()
            .map(|r| madar_loyalty::Reward {
                menu_item_id: r.menu_item_id.clone(),
                cost: r.cost_amount,
            })
            .collect(),
        any_item: scan.any_item,
        any_item_cost: scan.any_item_cost,
        max_per_order: scan.max_rewards_per_order,
        balance: scan.member.balance,
    }
}

/// What one unit of `line` costs, if this balance's programme lets it be taken
/// (madar-shared's `madar_loyalty::unit_cost`: a menu item, not a staff drink,
/// the first catalogue entry for the item — else the any-item cost — above
/// zero).
fn unit_cost_for(line: &RewardLineInput, scan: &LoyaltyScanView) -> Option<i64> {
    madar_loyalty::unit_cost(&plan_line(line), &programme_of(scan))
}

/// Minor units covering `units` of a line: whole units at the line's charged
/// per-unit price, never more than the line. The rule is madar-shared's
/// `madar_money::loyalty::covered_minor` (the server's too), pinned by its
/// `loyalty_reward_vectors.json`; the till states a line by its total and
/// quantity, so the per-unit price is `line_total / qty`.
pub fn covered_minor(line_total_minor: i64, qty: i64, units: i64) -> i64 {
    if qty <= 0 {
        return 0;
    }
    madar_money::loyalty::covered_minor(line_total_minor / qty, line_total_minor, units)
}

/// Apply the rules to the asked picks and describe every line.
///
/// Picks are honoured in the order given; a pick for a line that is gone or a
/// non-reward is dropped; units are clamped to the line; and
/// picks that would overrun the per-order cap or the balance are trimmed —
/// each trim named in `adjusted_reason` so the teller hears it before Charge,
/// not from the server after.
pub fn reward_board(
    lines: &[RewardLineInput],
    scan: &LoyaltyScanView,
    asked: &[RewardPick],
    locale: &str,
) -> RewardBoardView {
    let tr = |k: &str| crate::i18n::tr(locale, k);
    let balance = scan.member.balance.max(0);
    let cap = scan.max_rewards_per_order.filter(|c| *c > 0);
    // Which of the asked picks survive: madar-shared's planner in its TILL
    // mode (trim, and name the first trim), the same rules the server judges
    // the sale with strictly — so the sale Charge sends is one it takes.
    let plan_lines: Vec<madar_loyalty::Line> = lines.iter().map(plan_line).collect();
    let asks: Vec<madar_loyalty::Ask> = asked
        .iter()
        .map(|p| madar_loyalty::Ask {
            line: Some(p.line as usize),
            units: Some(i64::from(p.units)),
        })
        .collect();
    let plan = madar_loyalty::plan(
        &plan_lines,
        &programme_of(scan),
        &asks,
        madar_loyalty::Mode::Till,
    )
    .unwrap_or_default();
    let picks: Vec<RewardPick> = plan
        .lines
        .iter()
        .map(|p| RewardPick {
            line: p.line as u32,
            units: p.units as i32,
        })
        .collect();
    let cost = plan.cost;
    let claimed = plan.units;
    let reason: Option<String> = plan.trimmed.map(|t| match t {
        madar_loyalty::Trim::LineGone => tr("loyalty.reward_line_gone"),
        madar_loyalty::Trim::NotOnOffer => tr("loyalty.reward_not_on_offer"),
        madar_loyalty::Trim::LineShrank => tr("loyalty.reward_line_shrank"),
        madar_loyalty::Trim::OverCap => cap_reason(cap.unwrap_or(0), locale),
        madar_loyalty::Trim::BalanceShort => tr("loyalty.reward_balance_short"),
    });

    let states = lines
        .iter()
        .enumerate()
        .map(|(i, line)| {
            let unit = unit_cost_for(line, scan);
            let units = picks
                .iter()
                .find(|p| p.line as usize == i)
                .map(|p| p.units)
                .unwrap_or(0);
            let blocked_reason = match unit {
                None if line.is_staff_drink => Some(tr("loyalty.reward_no_staff_drink")),
                None => None,
                Some(_) if units >= line.qty => None,
                Some(_) if cap.is_some_and(|c| claimed >= c) => {
                    Some(cap_reason(cap.unwrap_or(0), locale))
                }
                Some(u) if balance - cost < u => Some(tr("loyalty.reward_balance_short")),
                Some(_) => None,
            };
            let can_add = unit.is_some() && units < line.qty && blocked_reason.is_none();
            RewardLineState {
                line: i as u32,
                claimable: unit.is_some(),
                unit_cost: unit.unwrap_or(0),
                units,
                can_add,
                blocked_reason,
                covered_minor: covered_minor(line.line_total_minor, line.qty as i64, units as i64),
                cost_label: unit
                    .map(|u| format!("{u} {}", balance_label(&scan.member.mode, locale)))
                    .unwrap_or_default(),
            }
        })
        .collect::<Vec<_>>();
    let covered = states.iter().map(|s| s.covered_minor).sum();
    RewardBoardView {
        lines: states,
        picks,
        cost,
        balance_after: balance - cost,
        units_claimed: claimed as i32,
        covered_minor: covered,
        adjusted_reason: reason,
    }
}

/// The tap on a line: cover one more unit, or — when it is fully covered or
/// can take no more — take its cover off. Returns the new asked picks; render
/// them through [`reward_board`].
pub fn toggle_reward(
    lines: &[RewardLineInput],
    scan: &LoyaltyScanView,
    picks: &[RewardPick],
    line: u32,
    locale: &str,
) -> Vec<RewardPick> {
    let board = reward_board(lines, scan, picks, locale);
    let mut next = board.picks.clone();
    let Some(state) = board.lines.get(line as usize) else {
        return next;
    };
    if !state.claimable {
        return next;
    }
    match next.iter_mut().find(|p| p.line == line) {
        Some(p) if state.can_add => p.units += 1,
        Some(_) => next.retain(|p| p.line != line),
        None if state.can_add => next.push(RewardPick { line, units: 1 }),
        None => {}
    }
    next
}

/// What the teller reads when a sale's rewards were recorded without points.
pub fn refusal_notice(reason: &str, locale: &str) -> String {
    format!(
        "{}: {reason}",
        crate::i18n::tr(locale, "loyalty.reward_refused")
    )
}

/// "Reward" or "Reward ×2", for a receipt or kitchen line.
pub fn reward_label(units: i64, locale: &str) -> String {
    let word = crate::i18n::tr(locale, "loyalty.reward");
    if units > 1 {
        format!("{word} ×{units}")
    } else {
        word
    }
}

fn cap_reason(cap: i64, locale: &str) -> String {
    if cap == 1 {
        crate::i18n::tr(locale, "loyalty.reward_cap_one")
    } else {
        crate::i18n::tr(locale, "loyalty.reward_cap_many").replace("{n}", &cap.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_counts_down_then_announces() {
        assert_eq!(progress_label(30, 100, "en"), "30 / 100");
        assert_eq!(progress_label(100, 100, "en"), "Reward earned");
        assert_eq!(progress_label(130, 100, "en"), "Reward earned");
        assert_eq!(progress_label(100, 100, "ar"), "المكافأة جاهزة");
        assert_eq!(balance_label("visits", "ar"), "طلبات");
        assert_eq!(balance_label("points", "ar"), "نقاط");
    }

    #[test]
    fn a_zero_threshold_does_not_announce_a_reward() {
        // Defensive: the server's column is CHECK (> 0), but a screen telling
        // every customer their reward was ready would be a bad way to find out.
        assert_eq!(progress_label(0, 0, "en"), "0 / 0");
    }

    #[test]
    fn a_whole_card_is_recognised_but_a_half_typed_one_is_not() {
        let token = "Mabcdefghijklmnopqrstuv"; // M + 22
        assert_eq!(token.len(), TOKEN_LEN);
        let got = classify_scan_input(token);
        assert_eq!(got.kind, "token");
        assert_eq!(got.value, token);

        // This is the case a keystroke-at-a-time USB wedge walks through on its
        // way to a full scan. Every prefix must stay `partial`, or the till
        // fires a lookup for a card nobody has finished scanning.
        for n in 1..TOKEN_LEN {
            assert_eq!(
                classify_scan_input(&token[..n]).kind,
                "partial",
                "prefix of length {n} must not look like a whole card"
            );
        }
    }

    #[test]
    fn a_phone_number_is_recognised_however_it_is_punctuated() {
        for raw in ["01000000001", "+20 100 000 0001", "0100-000-0001"] {
            assert_eq!(classify_scan_input(raw).kind, "phone", "{raw}");
        }
        // …and leaves in the one canonical form, however it was typed.
        for raw in ["01000000001", "+20 100 000 0001", "(010) 0000-0001", "٠١٠٠٠٠٠٠٠٠١", "201000000001"] {
            assert_eq!(classify_scan_input(raw).value, "201000000001", "{raw}");
        }
        // Too short to route an OTP to is not a phone number yet.
        assert_eq!(classify_scan_input("0100").kind, "partial");
    }

    #[test]
    fn junk_is_partial_rather_than_a_lookup() {
        // A camera that read a poster, or a teller leaning on the keyboard.
        assert_eq!(classify_scan_input("https://example.com").kind, "partial");
        assert_eq!(classify_scan_input("   ").kind, "partial");
        // Right length, wrong sentinel — another vendor's barcode.
        assert_eq!(
            classify_scan_input("Xabcdefghijklmnopqrstuv").kind,
            "partial"
        );
    }

    fn member(name: &str, balance: i32, target: i32) -> madar_api::models::MemberView {
        madar_api::models::MemberView {
            name: name.into(),
            balance,
            next_reward_cost: target,
            mode: "visits".into(),
            ..Default::default()
        }
    }

    fn result(points: i32, already: bool) -> madar_api::models::AwardResult {
        madar_api::models::AwardResult::new(
            already,
            member("Sara", 3, 5),
            Default::default(),
            points,
        )
    }

    #[test]
    fn a_first_press_says_the_points_went_on() {
        let out = award_outcome("en", &result(1, false));
        assert_eq!(out.headline, "Points added");
        assert_eq!(out.detail, "Sara — 3 orders · 3 / 5");
        assert!(!out.already_collected);
        assert!(!out.queued);
        assert_eq!(out.points_awarded, 1);
    }

    #[test]
    fn a_second_press_on_one_sale_says_already_collected() {
        // The endpoint is idempotent per order, so the second press is safe —
        // and must not claim to have added a second stamp. The balance shown is
        // the one that actually stands.
        let out = award_outcome("en", &result(0, true));
        assert_eq!(out.headline, "Already collected");
        assert!(out.already_collected);
        assert_eq!(out.points_awarded, 0);
        assert_eq!(out.detail, "Sara — 3 orders · 3 / 5");
    }

    #[test]
    fn a_sale_too_small_to_earn_says_so_rather_than_adding_nothing_loudly() {
        let out = award_outcome("en", &result(0, false));
        assert_eq!(out.headline, "No points for this sale");
        assert!(!out.already_collected);
    }

    #[test]
    fn a_queued_press_shows_no_balance_at_all() {
        // There is no balance yet, and a made-up one is a lie the customer can
        // read off the screen.
        let out = award_queued("en");
        assert!(out.member.is_none());
        assert!(out.queued);
        assert_eq!(out.headline, "Points queued");
        assert!(out.detail.contains("offline"));
    }

    #[test]
    fn every_outcome_is_phrased_in_arabic_too() {
        // Arabic is first class: a teller on an ar till must never be shown the
        // key, which is what an untranslated string resolves to.
        for out in [
            award_outcome("ar", &result(1, false)),
            award_outcome("ar", &result(0, true)),
            award_outcome("ar", &result(0, false)),
            award_queued("ar"),
        ] {
            assert!(!out.headline.starts_with("loyalty."), "{}", out.headline);
            assert!(!out.detail.starts_with("loyalty."), "{}", out.detail);
        }
    }

    #[test]
    fn the_window_closes_a_day_after_the_sale() {
        let sale = "2026-09-07T10:00:00+00:00";
        assert!(award_window_open(sale, "2026-09-07T10:00:01+00:00"));
        assert!(award_window_open(sale, "2026-09-08T09:59:00+00:00"));
        assert!(!award_window_open(sale, "2026-09-08T10:00:01+00:00"));
    }

    #[test]
    fn a_clock_behind_the_sale_closes_the_window_rather_than_opening_it() {
        // A till whose clock is wrong must not offer a button the server will
        // refuse — and must never offer one for a sale that has not happened.
        assert!(!award_window_open(
            "2026-09-07T10:00:00+00:00",
            "2026-09-07T09:00:00+00:00"
        ));
    }

    #[test]
    fn an_unreadable_timestamp_hides_the_button() {
        assert!(!award_window_open(
            "not a date",
            "2026-09-07T10:00:00+00:00"
        ));
        assert!(!award_window_open("2026-09-07T10:00:00+00:00", "nonsense"));
    }

    #[test]
    fn history_points_are_signed_for_a_column_of_numbers() {
        assert_eq!(points_label(13), "+13");
        assert_eq!(points_label(-100), "−100");
        assert_eq!(points_label(0), "+0");
    }

    #[test]
    fn a_programme_names_itself_in_the_tills_language() {
        let mut s = madar_api::models::LoyaltySettings::default();
        s.enabled = true;
        s.mode = "visits".into();
        s.program_name = "Rue Rewards".into();
        s.program_name_ar = Some(Some("مكافآت رو".into()));
        assert_eq!(programme_view(&s, "ar").program_name, "مكافآت رو");
        assert_eq!(programme_view(&s, "en").program_name, "Rue Rewards");
        // A stamp card counts orders, and says so before anyone is scanned.
        assert_eq!(programme_view(&s, "en").balance_label, "orders");
    }

    #[test]
    fn an_untranslated_name_still_shows_in_arabic() {
        let mut s = madar_api::models::LoyaltySettings::default();
        s.program_name = "Rue Rewards".into();
        s.program_name_ar = Some(None);
        assert_eq!(
            programme_view(&s, "ar").program_name,
            "Rue Rewards",
            "a blank translation must not render as an empty title"
        );
    }

    #[test]
    fn a_shop_with_no_programme_says_so() {
        let s = madar_api::models::LoyaltySettings::default();
        assert!(!programme_view(&s, "en").enabled);
    }

    // ── the reward board ─────────────────────────────────────────────────────

    fn scan(balance: i64, cap: Option<i64>, any_item: bool) -> LoyaltyScanView {
        LoyaltyScanView {
            member: member_view(&member("Ali", balance as i32, 5), "en"),
            rewards: vec![LoyaltyRewardView {
                menu_item_id: "latte".into(),
                name: "Latte".into(),
                price_minor: 5_000,
                cost_currency: "visits".into(),
                cost_amount: 5,
                cost_label: "5 orders".into(),
            }],
            recent: vec![],
            any_item,
            any_item_cost: 8,
            max_rewards_per_order: cap,
        }
    }

    fn line(item: &str, qty: i32, total: i64) -> RewardLineInput {
        RewardLineInput {
            name: item.into(),
            cart_index: None,
            ticket_line_id: None,
            menu_item_id: Some(item.into()),
            qty,
            line_total_minor: total,
            is_staff_drink: false,
        }
    }

    fn pick(line: u32, units: i32) -> RewardPick {
        RewardPick { line, units }
    }

    #[test]
    fn a_reward_covers_the_drink_as_chosen_and_only_the_catalogue_is_offered() {
        // Three oat lattes at 6,750 each; a cake that is not a reward.
        let lines = [line("latte", 3, 20_250), line("cake", 1, 9_000)];
        let b = reward_board(&lines, &scan(12, None, false), &[pick(0, 2)], "en");
        assert_eq!(b.picks, vec![pick(0, 2)]);
        assert_eq!(b.cost, 10);
        assert_eq!(b.balance_after, 2);
        assert_eq!(b.covered_minor, 13_500);
        assert!(!b.lines[1].claimable);
        assert!(!b.lines[0].can_add, "2 left on the card, a latte costs 5");
        assert_eq!(
            b.lines[0].blocked_reason.as_deref(),
            Some("Not enough on the card for another")
        );
    }

    #[test]
    fn the_per_order_cap_is_enforced_before_charge_and_says_so() {
        let lines = [line("latte", 3, 15_000)];
        let b = reward_board(&lines, &scan(50, Some(1), false), &[pick(0, 3)], "en");
        assert_eq!(b.picks, vec![pick(0, 1)]);
        assert_eq!(
            b.adjusted_reason.as_deref(),
            Some("One reward per order here")
        );
        assert_eq!(
            b.lines[0].blocked_reason.as_deref(),
            Some("One reward per order here")
        );
        let ar = reward_board(&lines, &scan(50, Some(2), false), &[pick(0, 3)], "ar");
        assert_eq!(ar.picks, vec![pick(0, 2)]);
        assert!(ar.adjusted_reason.unwrap().contains('2'));
    }

    #[test]
    fn a_line_reduced_or_removed_after_the_tap_clamps_or_drops_its_reward() {
        let s = scan(50, None, false);
        let shrunk = reward_board(&[line("latte", 1, 5_000)], &s, &[pick(0, 3)], "en");
        assert_eq!(shrunk.picks, vec![pick(0, 1)]);
        assert!(shrunk.adjusted_reason.is_some());
        let gone = reward_board(&[], &s, &[pick(0, 1)], "en");
        assert!(gone.picks.is_empty());
        assert_eq!(gone.covered_minor, 0);
        // A line replaced by a non-reward item keeps no reward.
        let replaced = reward_board(&[line("cake", 1, 9_000)], &s, &[pick(0, 1)], "en");
        assert!(replaced.picks.is_empty());
    }

    #[test]
    fn no_item_zero_cost_and_any_item_follow_the_servers_rules() {
        let mut no_item = line("latte", 1, 5_000);
        no_item.menu_item_id = None;
        let b = reward_board(&[no_item], &scan(50, None, true), &[pick(0, 1)], "en");
        assert!(b.picks.is_empty());
        assert!(!b.lines[0].claimable);
        let any = reward_board(
            &[line("cake", 1, 9_000)],
            &scan(8, None, true),
            &[pick(0, 1)],
            "en",
        );
        assert_eq!(any.cost, 8);
        let mut free = scan(50, None, false);
        free.rewards[0].cost_amount = 0;
        let zero = reward_board(&[line("latte", 1, 5_000)], &free, &[pick(0, 1)], "en");
        assert!(
            zero.picks.is_empty(),
            "a reward priced at nothing is not offered"
        );
    }

    #[test]
    fn a_tap_adds_a_unit_until_the_line_is_covered_then_clears_it() {
        let lines = [line("latte", 2, 10_000)];
        let s = scan(50, None, false);
        let one = toggle_reward(&lines, &s, &[], 0, "en");
        assert_eq!(one, vec![pick(0, 1)]);
        let two = toggle_reward(&lines, &s, &one, 0, "en");
        assert_eq!(two, vec![pick(0, 2)]);
        assert!(toggle_reward(&lines, &s, &two, 0, "en").is_empty());
        assert!(toggle_reward(&lines, &s, &[], 5, "en").is_empty());
    }

    #[test]
    fn two_rewards_that_outrun_the_balance_keep_the_first() {
        let lines = [line("latte", 1, 5_000), line("latte", 1, 5_000)];
        let b = reward_board(
            &lines,
            &scan(7, None, false),
            &[pick(0, 1), pick(1, 1)],
            "en",
        );
        assert_eq!(b.picks, vec![pick(0, 1)]);
        assert_eq!(
            b.adjusted_reason.as_deref(),
            Some("Not enough on the card for another")
        );
    }

    /// madar-loyalty's plan vectors (the rules the server judges a sale with)
    /// through this till's board: every case a till can ask — a named line and
    /// a number of units — trims to the crate's TILL plan, cost and all.
    #[test]
    fn the_board_trims_as_the_shared_planner_does() {
        use madar_loyalty::plan::vectors::PlanVector;
        let vectors: Vec<PlanVector> =
            serde_json::from_str(madar_loyalty::vectors::PLAN).unwrap();
        let mut checked = 0;
        for v in vectors
            .iter()
            .filter(|v| v.asks.iter().all(|a| a.line.is_some() && a.units.is_some()))
        {
            let lines: Vec<RewardLineInput> = v
                .lines
                .iter()
                .map(|l| RewardLineInput {
                    name: "line".into(),
                    cart_index: None,
                    ticket_line_id: None,
                    menu_item_id: l.menu_item_id.clone(),
                    qty: l.quantity as i32,
                    line_total_minor: 1_000 * l.quantity,
                    is_staff_drink: l.is_staff_drink,
                })
                .collect();
            let mut sc = scan(0, v.programme.max_per_order, v.programme.any_item);
            sc.member.balance = v.programme.balance;
            sc.any_item_cost = v.programme.any_item_cost;
            sc.rewards = v
                .programme
                .rewards
                .iter()
                .map(|r| LoyaltyRewardView {
                    menu_item_id: r.menu_item_id.clone(),
                    name: "reward".into(),
                    price_minor: 0,
                    cost_currency: "points".into(),
                    cost_amount: r.cost,
                    cost_label: String::new(),
                })
                .collect();
            let asked: Vec<RewardPick> = v
                .asks
                .iter()
                .map(|a| pick(a.line.unwrap() as u32, a.units.unwrap() as i32))
                .collect();
            let b = reward_board(&lines, &sc, &asked, "en");
            let want: Vec<RewardPick> = v
                .till
                .lines
                .iter()
                .map(|p| pick(p.line as u32, p.units as i32))
                .collect();
            assert_eq!(b.picks, want, "{}", v.name);
            assert_eq!(b.cost, v.till.cost, "{}", v.name);
            assert_eq!(i64::from(b.units_claimed), v.till.units, "{}", v.name);
            assert_eq!(b.adjusted_reason.is_some(), v.till.trimmed.is_some(), "{}", v.name);
            checked += 1;
        }
        assert!(checked >= 20, "checked {checked}");
    }
}
