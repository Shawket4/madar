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
//! to look this up". EARNING is online-only too (owner, 2026-10-17): pressing
//! "add points" with no connection is refused with a sentence saying so, and
//! nothing is queued. The receipt keeps its button for the 24-hour window, so
//! the teller presses it again once the till is online. The only awards that
//! ever drain from the outbox are ones an earlier build queued (see
//! `AWARD_REFUSAL_CODES`).

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
    /// Every stamp track on the card, track 1 first, when the shop runs more
    /// than one; EMPTY otherwise (one track, a points programme, an older
    /// server), and then every screen is exactly today's. The fields above
    /// stay track 1's.
    pub tracks: Vec<LoyaltyTrackView>,
}

/// One stamp track on a member's card (the server's `MemberTrack`).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyTrackView {
    /// 1 to 4; track 1 is the programme's own card.
    pub position: u32,
    /// In the till's language; track 1 unnamed reads as its balance word.
    pub name: String,
    /// Stamps that fill the card (the reward's cost on this track).
    pub size: i64,
    pub balance: i64,
    /// Rewards already earned on this track.
    pub rewards_ready: i64,
    /// `#RRGGBB`, else the screen's own colour.
    pub colour: Option<String>,
}

/// What a track 2-4 offers at the till: each of its items at its size.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyTrackRewardsView {
    pub position: u32,
    pub rewards: Vec<LoyaltyRewardView>,
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
    /// Tracks 2-4's rewards (`rewards` stays track 1's). Empty unless the
    /// card has more than one track.
    pub track_rewards: Vec<LoyaltyTrackRewardsView>,
    /// The member's birthday gift (one free item), while it is open or was
    /// used this time; `None` otherwise and from an older server.
    pub birthday_gift: Option<LoyaltyGiftView>,
}

/// The birthday gift as the till shows it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyGiftView {
    /// Ready to hand over (`open` and not past its last day); `false` once
    /// claimed.
    pub open: bool,
    /// RFC3339: usable until this instant.
    pub valid_until: String,
    /// The last day it can be used ("21 Nov"), in the till's language.
    pub until_label: String,
    /// "Any item" may be the gift here; `None` from a server older than
    /// api v1.24.0, which then reads the scan's own `any_item`.
    pub any_item: Option<bool>,
    /// The branch's whole reward catalogue (item ids), whatever the balance;
    /// `None` from an older server, which then reads the scan's `rewards`
    /// (only what the balance affords: it offers fewer lines, never more).
    pub reward_item_ids: Option<Vec<String>>,
}

/// The gift's part of the Charge screen: which lines may be the free item
/// and the one picked, if it still may be.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GiftBoardView {
    /// An open gift is on the card: the section shows.
    pub open: bool,
    /// "Birthday gift: one free item · until 21 Nov".
    pub headline: String,
    /// Lines that may be the gift (positions in the board's lines). The
    /// teller picks one; even a single candidate is never picked for them,
    /// the gift being theirs to keep for another day.
    pub eligible: Vec<u32>,
    /// The picked line, if it still may be the gift.
    pub line: Option<u32>,
    /// Minor units the gift takes off the bill (one unit of its line).
    pub covered_minor: i64,
    /// Why nothing can be the gift on this sale, in the till's language.
    pub note: Option<String>,
}

/// What came of pressing "add points" on a sale.
///
/// The outcomes a teller has to be able to tell apart are decided HERE, from
/// what the server said, and phrased here too. "Added" and "already collected"
/// are different facts about the customer's card, and a till that guessed
/// between them would eventually claim to have added points it did not add.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyAwardOutcome {
    /// The member's standing after the call. `None` only for an outcome with no
    /// balance to show, and inventing one is a lie the customer can read off the
    /// screen. Always `Some` today: a press that is not answered is an error.
    pub member: Option<LoyaltyMemberView>,
    /// Always false since earning went online-only: a press the server did not
    /// answer is an error, never a queued op. Kept so the bridge type (and an
    /// older Dart build reading it) does not change shape.
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
    /// What each track earned on this press, track 1 first, when the card has
    /// more than one track; empty otherwise.
    pub tracks: Vec<LoyaltyTrackAward>,
}

/// One track's share of an award.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyTrackAward {
    pub position: u32,
    pub name: String,
    /// Stamps this press added on the track.
    pub awarded: i64,
    /// Where the track stands now.
    pub balance: i64,
    pub size: i64,
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
        tracks: track_awards(r, locale),
    }
}

/// Each track's share of an award: track 1 is `points_awarded`, tracks 2-4
/// come from the result's `tracks`. Empty for a one-track card.
fn track_awards(r: &madar_api::models::AwardResult, locale: &str) -> Vec<LoyaltyTrackAward> {
    let earned = r.tracks.clone().flatten().unwrap_or_default();
    member_view(&r.member, locale)
        .tracks
        .into_iter()
        .map(|t| LoyaltyTrackAward {
            awarded: if t.position == 1 {
                r.points_awarded as i64
            } else {
                earned
                    .iter()
                    .find(|e| e.position == t.position)
                    .map_or(0, |e| e.points_awarded as i64)
            },
            position: t.position,
            name: t.name,
            balance: t.balance,
            size: t.size,
        })
        .collect()
}

/// The detail an award refused for want of a connection carries; the host maps
/// it to `loyalty.award_offline` (see `coreDetailKeys`).
pub const AWARD_OFFLINE: &str = "points can only be added online";

/// The refusals the server gives an award a stable code for (MadarRust
/// `loyalty::award`), and the words each has. `sync.err_<code>` is also where
/// the stuck list looks (`outbox_words`), so one key says the same thing to a
/// teller who pressed the button just now and to one reading a stuck row left
/// by an older build. Two more codes (`LOYALTY_WINDOW_FUTURE`,
/// `LOYALTY_WINDOW_BEFORE_SALE`) have no words of their own: a till with a sane
/// clock cannot cause them, and the server's sentence is shown as it always was.
pub const AWARD_REFUSAL_CODES: [(&str, &str); 6] = [
    ("LOYALTY_CARD_NOT_MEMBER", "sync.err_loyalty_card_not_member"),
    ("LOYALTY_SALE_NOT_ON_SERVER", "sync.err_loyalty_sale_not_on_server"),
    ("LOYALTY_SALE_OTHER_SHOP", "sync.err_loyalty_sale_other_shop"),
    ("LOYALTY_SALE_VOIDED", "sync.err_loyalty_sale_voided"),
    ("LOYALTY_WINDOW_CLOSED", "sync.err_loyalty_window_closed"),
    ("LOYALTY_PROGRAM_OFF", "sync.err_loyalty_program_off"),
];

/// The teller's words for an award the server refused, from its `{error, code}`
/// body, as `(code, words)`. `None` for a body with no code or a code this build
/// has no words for (an older server): the caller then falls back to the
/// wording it always had.
pub fn award_refusal_words(locale: &str, body: &str) -> Option<(String, String)> {
    let code = crate::net::extract_error_code(body)?;
    let (_, key) = AWARD_REFUSAL_CODES.iter().find(|(c, _)| *c == code)?;
    Some((code, crate::i18n::tr(locale, key)))
}

/// How long after a sale its points may still be claimed.
///
/// Kept in lock-step with the server's `loyalty::award::AWARD_WINDOW_HOURS`. The
/// client copy exists so the button can hide itself and a press can be refused
/// without a round trip; the SERVER's copy is the one that
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

/// The outbox payload of an award an EARLIER build queued (op_type
/// `"award_loyalty_points"`). Nothing enqueues one any more; the drain keeps
/// reading it so those ops still reach the server.
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
    pub fn is_ready(&self) -> bool {
        self.kind != "partial"
    }
}

/// A member token is `M` + 22 base64url characters — the shape the server
/// mints (madar-shared's `madar_ids::member`). A half-typed buffer is never
/// mistaken for a whole card.
#[cfg(test)]
const TOKEN_LEN: usize = madar_ids::member::TOKEN_LEN;

/// Classify a captured string. The rule is madar-shared's (`madar_ids::scan`),
/// the one the loyalty teller page runs too; this only fits it to the bridge.
pub fn classify_scan_input(raw: &str) -> LoyaltyScanInput {
    use madar_ids::scan::{classify, Kind};
    let s = classify(raw);
    LoyaltyScanInput {
        kind: match s.kind {
            Kind::Token => "token",
            Kind::Phone => "phone",
            Kind::Partial => "partial",
        }
        .into(),
        value: s.value,
    }
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
/// order's own lines out of its own tables. Earning is online-only, so the
/// answer comes back off the same rows the server already holds, and no till
/// ever computes it. Nothing
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
        tracks: m
            .tracks
            .clone()
            .flatten()
            .filter(|t| t.len() > 1)
            .unwrap_or_default()
            .iter()
            .map(|t| LoyaltyTrackView {
                position: t.position,
                name: match crate::menu::pick_lang(&t.name_en, &t.name_ar, locale) {
                    n if n.trim().is_empty() => balance_label(&m.mode, locale),
                    n => n,
                },
                size: t.size as i64,
                balance: t.balance as i64,
                rewards_ready: t.rewards_ready as i64,
                colour: t.colour.clone().flatten(),
            })
            .collect(),
    }
}

fn reward_view(r: &madar_api::models::RewardItem, unit: &str) -> LoyaltyRewardView {
    LoyaltyRewardView {
        menu_item_id: r.menu_item_id.to_string(),
        name: r.name.clone(),
        price_minor: r.base_price as i64,
        cost_currency: r.cost_currency.clone(),
        cost_amount: r.cost_amount as i64,
        cost_label: format!("{} {unit}", r.cost_amount),
    }
}

pub fn scan_view(s: &madar_api::models::ScanResult, locale: &str) -> LoyaltyScanView {
    LoyaltyScanView {
        member: member_view(&s.member, locale),
        rewards: s
            .rewards
            .iter()
            .map(|r| reward_view(r, &balance_label(&r.cost_currency, locale)))
            .collect(),
        track_rewards: s
            .track_rewards
            .clone()
            .flatten()
            .unwrap_or_default()
            .iter()
            .filter(|t| t.position > 1)
            .map(|t| LoyaltyTrackRewardsView {
                position: t.position,
                rewards: t
                    .rewards
                    .iter()
                    .map(|r| reward_view(r, &crate::i18n::tr(locale, "loyalty.unit_stamps")))
                    .collect(),
            })
            .collect(),
        birthday_gift: s
            .birthday_gift
            .clone()
            .flatten()
            .map(|g| gift_view(&g, chrono::Utc::now().fixed_offset(), locale)),
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

// ── The birthday gift ────────────────────────────────────────────────────────

/// The gift as of `now`: open only while the server says `open` and its
/// window has not passed (a lookup held on screen past midnight on the last
/// day shows it used up rather than offering what the server will refuse).
pub fn gift_view(
    g: &madar_api::models::BirthdayGiftView,
    now: chrono::DateTime<chrono::FixedOffset>,
    locale: &str,
) -> LoyaltyGiftView {
    // The last day: the instant it ends, minus a second (an end at midnight
    // is the day before), in the offset the server wrote.
    let last = g.valid_until - chrono::Duration::seconds(1);
    use chrono::Datelike;
    LoyaltyGiftView {
        open: g.status == "open" && g.valid_until > now,
        valid_until: g.valid_until.to_rfc3339(),
        until_label: format!(
            "{} {}",
            last.day(),
            crate::i18n::tr(locale, &format!("staff.month_{}", last.month()))
        ),
        any_item: g.any_item.flatten(),
        reward_item_ids: g
            .reward_item_ids
            .clone()
            .flatten()
            .map(|ids| ids.iter().map(ToString::to_string).collect()),
    }
}

/// The gift's programme as madar-shared's rule reads it: the catalogue and
/// "any item" the lookup sent with the gift (the whole catalogue, api
/// v1.24.0+), else the scan's own (an older server: what the balance affords,
/// so fewer lines, never more).
pub fn gift_programme(scan: &LoyaltyScanView) -> madar_loyalty::GiftProgramme {
    let g = scan.birthday_gift.as_ref();
    madar_loyalty::GiftProgramme {
        reward_items: g
            .and_then(|g| g.reward_item_ids.clone())
            .unwrap_or_else(|| scan.rewards.iter().map(|r| r.menu_item_id.clone()).collect()),
        any_item: g.and_then(|g| g.any_item).unwrap_or(scan.any_item),
        open: g.is_some_and(|g| g.open),
    }
}

/// The lines that may be the gift, `covered` (lines a reward takes) set
/// aside: madar-shared's `gift_eligible`, the server's rule.
pub fn gift_eligible_lines(lines: &[RewardLineInput], scan: &LoyaltyScanView, covered: &[usize]) -> Vec<u32> {
    let programme = gift_programme(scan);
    lines
        .iter()
        .enumerate()
        .filter(|(i, l)| madar_loyalty::gift_eligible(&plan_line(l), covered.contains(i), &programme))
        .map(|(i, _)| i as u32)
        .collect()
}

/// Whether the gift may go on `line` (madar-shared's `plan_gift`), as the
/// teller's words: `loyalty.gift_gone` (no open gift) or
/// `loyalty.gift_not_eligible` (the line or the item).
pub fn gift_check(
    lines: &[RewardLineInput],
    scan: &LoyaltyScanView,
    line: Option<usize>,
    covered: &[usize],
) -> Result<(), &'static str> {
    let plan_lines: Vec<madar_loyalty::Line> = lines.iter().map(plan_line).collect();
    match madar_loyalty::plan_gift(&plan_lines, &gift_programme(scan), line, covered) {
        Ok(_) => Ok(()),
        Err(madar_loyalty::GiftRefusal::None) => Err("loyalty.gift_gone"),
        Err(_) => Err("loyalty.gift_not_eligible"),
    }
}

/// The gift section for these lines: what may be the gift once the rewards
/// in `picks` are set aside (a line is a reward OR the gift), and whether the
/// teller's `asked` line still may.
pub fn gift_board(
    lines: &[RewardLineInput],
    scan: &LoyaltyScanView,
    picks: &[RewardPick],
    asked: Option<u32>,
    locale: &str,
) -> GiftBoardView {
    let Some(g) = scan.birthday_gift.as_ref().filter(|g| g.open) else {
        return GiftBoardView {
            open: false,
            headline: String::new(),
            eligible: Vec::new(),
            line: None,
            covered_minor: 0,
            note: None,
        };
    };
    let covered: Vec<usize> = reward_board(lines, scan, picks, locale)
        .picks
        .iter()
        .map(|p| p.line as usize)
        .collect();
    let eligible = gift_eligible_lines(lines, scan, &covered);
    let line = asked.filter(|a| eligible.contains(a));
    GiftBoardView {
        open: true,
        headline: crate::i18n::tr(locale, "loyalty.gift_headline").replace("{date}", &g.until_label),
        note: eligible
            .is_empty()
            .then(|| crate::i18n::tr(locale, "loyalty.gift_nothing")),
        covered_minor: line
            .and_then(|i| lines.get(i as usize))
            .map_or(0, |l| covered_minor(l.line_total_minor, l.qty as i64, 1)),
        eligible,
        line,
    }
}

/// The gift on `line` in the shape a checkout or settle carries it (one unit,
/// priced like a reward; the core sends it as `loyalty_birthday_gift`).
pub fn gift_redemption(
    lines: &[RewardLineInput],
    line: u32,
) -> Option<crate::checkout::CheckoutRedemption> {
    let l = lines.get(line as usize)?;
    Some(crate::checkout::CheckoutRedemption {
        item_index: l.cart_index.unwrap_or(0),
        ticket_line_id: l.ticket_line_id.clone(),
        units: 1,
        track: None,
        gift: true,
    })
}

/// The receipt's word for a covered line: "Birthday gift", or "Reward"
/// (×units) with the track's name for a track 2-4 reward.
pub fn cover_label(units: i64, track_name: Option<&str>, gift: bool, locale: &str) -> String {
    if gift {
        return crate::i18n::tr(locale, "loyalty.gift_line");
    }
    match track_name.filter(|n| !n.is_empty()) {
        Some(n) => format!("{} · {n}", reward_label(units, locale)),
        None => reward_label(units, locale),
    }
}

/// Tracks 2-4's names from the branch's synced loyalty settings (the feed's
/// `loyalty.tracks`), in the till's language; empty for a one-track card or
/// an older server.
pub(crate) fn feed_track_names(store: &crate::store::Store, branch_id: &str, locale: &str) -> Vec<(u32, String)> {
    crate::sync_pull::branch_setting(store, branch_id, "loyalty")
        .and_then(|v| v.get("tracks").and_then(serde_json::Value::as_array).cloned())
        .unwrap_or_default()
        .iter()
        .filter_map(|t| {
            let pos = t.get("position")?.as_u64()? as u32;
            let s = |k: &str| t.get(k).and_then(serde_json::Value::as_str).unwrap_or_default().to_string();
            (pos > 1).then(|| (pos, crate::menu::pick_lang(&s("name_en"), &s("name_ar"), locale)))
        })
        .collect()
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
    /// The line is a COMBO (C7: its items earn stamps, but no reward is
    /// taken inside a combo — the server refuses `REWARD_IN_COMBO`).
    pub in_combo: bool,
    /// The line is in an applied DEAL: already discounted, never a reward too.
    pub in_deal: bool,
}

/// A reward applied to one line: which line (its position in the list the
/// board was built from) and how many of its units.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RewardPick {
    pub line: u32,
    pub units: i32,
    /// The stamp track that pays: 1 (the programme's own card) unless the
    /// card has more than one track.
    pub track: u32,
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
    /// The track covering it; 0 when nothing covers it.
    pub track: u32,
    /// The tracks a tap could cover it with. Two or more: the till asks
    /// which, nothing preselected ([`toggle_reward_on_track`]). Empty on a
    /// one-track card.
    pub track_choices: Vec<u32>,
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
    /// Each track's balance after `picks`, track 1 first, on a card with more
    /// than one track; empty otherwise (`balance_after` is track 1's).
    pub tracks_after: Vec<LoyaltyTrackAfter>,
}

/// A track's balance once the ticked rewards are taken.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoyaltyTrackAfter {
    pub position: u32,
    pub name: String,
    pub balance_after: i64,
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
            in_combo: l.kind == crate::menu::KIND_COMBO,
            in_deal: l.deal_cut_minor > 0,
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
            in_combo: l.is_combo,
            in_deal: false,
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
        // The birthday gift is not a reward pick (see `gift_board`).
        .filter(|r| !r.gift)
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
                track: r.track.unwrap_or(1),
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
                // Track 1 is named by saying nothing, as every released till does.
                track: (p.track > 1).then_some(p.track),
                gift: false,
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
        // A line in a deal is as closed to a reward as a combo is.
        in_combo: line.in_combo || line.in_deal,
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
    if scan.member.tracks.len() > 1 {
        return tracks_board(lines, scan, asked, locale);
    }
    // One track: today's board, untouched (a pick on another track cannot
    // exist without a multi-track card, and is dropped here if it does).
    let asked: Vec<RewardPick> = asked.iter().filter(|p| p.track <= 1).cloned().collect();
    let asked = &asked[..];
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
            track: 1,
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
        madar_loyalty::Trim::InCombo => tr("combo.reward"),
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
                None if line.in_combo => Some(tr("combo.reward")),
                None if line.in_deal => Some(tr("deal.reward")),
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
                track: if units > 0 { 1 } else { 0 },
                track_choices: Vec::new(),
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
        tracks_after: Vec::new(),
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
        // Two tracks could pay: the till asks (toggle_reward_on_track).
        None if state.track_choices.len() > 1 => {}
        None if state.can_add => next.push(RewardPick {
            line,
            units: 1,
            track: state.track_choices.first().copied().unwrap_or(1),
        }),
        None => {}
    }
    next
}

/// The teller's answer to "which card pays?": cover one unit of an uncovered
/// `line` on `track`, if that track may take it now.
pub fn toggle_reward_on_track(
    lines: &[RewardLineInput],
    scan: &LoyaltyScanView,
    picks: &[RewardPick],
    line: u32,
    track: u32,
    locale: &str,
) -> Vec<RewardPick> {
    let board = reward_board(lines, scan, picks, locale);
    let mut next = board.picks.clone();
    let ok = board.lines.get(line as usize).is_some_and(|s| {
        s.units == 0 && s.can_add && s.track_choices.contains(&track)
    });
    if ok {
        next.push(RewardPick { line, units: 1, track });
    }
    next
}

/// Every track's programme as the shared planner reads it: track 1 is
/// [`programme_of`], tracks 2-4 their rewards at their size, each with the
/// member's balance on it.
fn track_programmes(scan: &LoyaltyScanView) -> Vec<madar_loyalty::tracks::TrackProgramme> {
    let balance = |pos: u32| {
        scan.member
            .tracks
            .iter()
            .find(|t| t.position == pos)
            .map_or(0, |t| t.balance)
    };
    let mut out = vec![madar_loyalty::tracks::TrackProgramme {
        track: 1,
        programme: programme_of(scan),
    }];
    for t in &scan.track_rewards {
        out.push(madar_loyalty::tracks::TrackProgramme {
            track: t.position as u8,
            programme: madar_loyalty::Programme {
                rewards: t
                    .rewards
                    .iter()
                    .map(|r| madar_loyalty::Reward {
                        menu_item_id: r.menu_item_id.clone(),
                        cost: r.cost_amount,
                    })
                    .collect(),
                balance: balance(t.position),
                ..Default::default()
            },
        });
    }
    out
}

/// The board on a card with several tracks: madar-shared's `plan_tracks`
/// (one reward per line, each track its own balance, one shared cap).
fn tracks_board(
    lines: &[RewardLineInput],
    scan: &LoyaltyScanView,
    asked: &[RewardPick],
    locale: &str,
) -> RewardBoardView {
    use madar_loyalty::tracks::{plan_tracks, TrackAsk};
    let tr = |k: &str| crate::i18n::tr(locale, k);
    let cap = scan.max_rewards_per_order.filter(|c| *c > 0);
    let progs = track_programmes(scan);
    let plan_lines: Vec<madar_loyalty::Line> = lines.iter().map(plan_line).collect();
    let asks: Vec<TrackAsk> = asked
        .iter()
        .map(|p| TrackAsk {
            line: Some(p.line as usize),
            units: Some(i64::from(p.units)),
            track: Some(p.track.max(1) as u8),
        })
        .collect();
    let plan = plan_tracks(&plan_lines, &progs, &asks, cap, madar_loyalty::Mode::Till)
        .unwrap_or_default();
    // The surviving picks, in the order they were asked.
    let mut picks: Vec<RewardPick> = Vec::new();
    for p in asked {
        if let Some((t, u)) = plan.cover(p.line as usize) {
            if !picks.iter().any(|x| x.line == p.line) {
                picks.push(RewardPick { line: p.line, units: u as i32, track: u32::from(t) });
            }
        }
    }
    let spent = |t: u8| {
        plan.tracks
            .iter()
            .find(|x| x.track == t)
            .map_or(0, |x| x.plan.cost)
    };
    let claimed = plan.units;
    let at_cap = cap.is_some_and(|c| claimed >= c);
    let name_of = |pos: u32| {
        scan.member
            .tracks
            .iter()
            .find(|t| t.position == pos)
            .map(|t| t.name.clone())
            .unwrap_or_default()
    };
    // "5 orders" on track 1, as today; "6 stamps · Sandwiches" on the others.
    let cost_of = |t: u8, u: i64| {
        if t == 1 {
            format!("{u} {}", balance_label(&scan.member.mode, locale))
        } else {
            format!("{u} {} · {}", tr("loyalty.unit_stamps"), name_of(u32::from(t)))
        }
    };
    let reason: Option<String> = plan.trimmed.map(|t| match t {
        madar_loyalty::Trim::LineGone => tr("loyalty.reward_line_gone"),
        madar_loyalty::Trim::NotOnOffer => tr("loyalty.reward_not_on_offer"),
        madar_loyalty::Trim::LineShrank => tr("loyalty.reward_line_shrank"),
        madar_loyalty::Trim::OverCap => cap_reason(cap.unwrap_or(0), locale),
        madar_loyalty::Trim::BalanceShort => tr("loyalty.reward_balance_short"),
        madar_loyalty::Trim::InCombo => tr("combo.reward"),
    });
    let states = lines
        .iter()
        .enumerate()
        .map(|(i, line)| {
            let pl = plan_line(line);
            // (track, unit cost, balance left on it) for every track offering it.
            let offers: Vec<(u8, i64, i64)> = progs
                .iter()
                .filter_map(|p| {
                    madar_loyalty::unit_cost(&pl, &p.programme)
                        .map(|u| (p.track, u, p.programme.balance.max(0) - spent(p.track)))
                })
                .collect();
            let cover = plan.cover(i);
            let units = cover.map_or(0, |(_, u)| u as i32);
            let (unit, choices): (Option<(u8, i64)>, Vec<u32>) = match cover {
                Some((t, _)) => (offers.iter().find(|o| o.0 == t).map(|o| (o.0, o.1)), Vec::new()),
                None => {
                    let c: Vec<u32> = offers
                        .iter()
                        .filter(|o| o.2 >= o.1)
                        .map(|o| u32::from(o.0))
                        .collect();
                    let first = offers.iter().find(|o| o.2 >= o.1).or(offers.first());
                    (first.map(|o| (o.0, o.1)), c)
                }
            };
            let affordable = match cover {
                Some((t, _)) => offers.iter().any(|o| o.0 == t && o.2 >= o.1),
                None => !choices.is_empty(),
            };
            let blocked_reason = match unit {
                None if line.is_staff_drink => Some(tr("loyalty.reward_no_staff_drink")),
                None if line.in_combo => Some(tr("combo.reward")),
                None if line.in_deal => Some(tr("deal.reward")),
                None => None,
                Some(_) if units >= line.qty => None,
                Some(_) if at_cap => Some(cap_reason(cap.unwrap_or(0), locale)),
                Some(_) if !affordable => Some(tr("loyalty.reward_balance_short")),
                Some(_) => None,
            };
            let can_add = unit.is_some() && units < line.qty && blocked_reason.is_none();
            // One offer: its cost. Several: each, so the teller sees both prices.
            let cost_label = match (cover, offers.len()) {
                (Some((t, _)), _) => unit.map(|(_, u)| cost_of(t, u)).unwrap_or_default(),
                (None, 0) => String::new(),
                (None, _) => offers
                    .iter()
                    .map(|o| cost_of(o.0, o.1))
                    .collect::<Vec<_>>()
                    .join(" / "),
            };
            RewardLineState {
                line: i as u32,
                claimable: unit.is_some(),
                unit_cost: unit.map_or(0, |u| u.1),
                units,
                can_add,
                blocked_reason,
                covered_minor: covered_minor(line.line_total_minor, line.qty as i64, units as i64),
                cost_label,
                track: cover.map_or(0, |(t, _)| u32::from(t)),
                track_choices: if units == 0 && can_add { choices } else { Vec::new() },
            }
        })
        .collect::<Vec<_>>();
    let covered = states.iter().map(|s| s.covered_minor).sum();
    let tracks_after = scan
        .member
        .tracks
        .iter()
        .map(|t| LoyaltyTrackAfter {
            position: t.position,
            name: t.name.clone(),
            balance_after: t.balance - spent(t.position as u8),
        })
        .collect();
    RewardBoardView {
        lines: states,
        picks,
        cost: plan.tracks.iter().map(|t| t.plan.cost).sum(),
        balance_after: scan.member.balance.max(0) - spent(1),
        units_claimed: claimed as i32,
        covered_minor: covered,
        adjusted_reason: reason,
        tracks_after,
    }
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
    fn every_outcome_is_phrased_in_arabic_too() {
        // Arabic is first class: a teller on an ar till must never be shown the
        // key, which is what an untranslated string resolves to.
        for out in [
            award_outcome("ar", &result(1, false)),
            award_outcome("ar", &result(0, true)),
            award_outcome("ar", &result(0, false)),
        ] {
            assert!(!out.headline.starts_with("loyalty."), "{}", out.headline);
            assert!(!out.detail.starts_with("loyalty."), "{}", out.detail);
        }
    }

    /// The six server codes, with the words each must say. English is the
    /// owner's wording; Arabic must be real Arabic, not the key.
    const EXPECTED_EN: [(&str, &str); 6] = [
        ("LOYALTY_CARD_NOT_MEMBER", "That card belongs to another shop"),
        (
            "LOYALTY_SALE_NOT_ON_SERVER",
            "That sale hasn't reached the server yet; try again after it syncs",
        ),
        ("LOYALTY_SALE_OTHER_SHOP", "That sale is from another shop"),
        ("LOYALTY_SALE_VOIDED", "That sale was voided"),
        (
            "LOYALTY_WINDOW_CLOSED",
            "The 24-hour window for this sale has closed",
        ),
        (
            "LOYALTY_PROGRAM_OFF",
            "Loyalty is switched off for this branch",
        ),
    ];

    #[test]
    fn each_award_refusal_code_has_words_in_both_languages() {
        for (code, en) in EXPECTED_EN {
            let body = format!(r#"{{"error":"Conflict: whatever","code":"{code}"}}"#);
            let (got, words) = award_refusal_words("en", &body).expect(code);
            assert_eq!(got, code);
            assert_eq!(words, en, "{code}");
            let (_, ar) = award_refusal_words("ar", &body).expect(code);
            assert_ne!(ar, en, "{code}: Arabic is the English or a bare key");
            assert!(!ar.starts_with("sync."), "{code}: {ar}");
            assert!(
                ar.chars().any(|c| ('\u{0600}'..='\u{06FF}').contains(&c)),
                "{code}: {ar}"
            );
        }
        // The table and the expectations name the same six codes.
        assert_eq!(AWARD_REFUSAL_CODES.len(), EXPECTED_EN.len());
    }

    #[test]
    fn an_older_server_without_a_code_falls_back_to_todays_wording() {
        assert!(award_refusal_words("en", r#"{"error":"Conflict: That sale was voided"}"#).is_none());
        assert!(award_refusal_words("en", r#"{"error":"x","code":"LOYALTY_WINDOW_FUTURE"}"#).is_none());
        assert!(award_refusal_words("en", "<html>nope</html>").is_none());
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
        let s = madar_api::models::LoyaltySettings {
            enabled: true,
            mode: "visits".into(),
            program_name: "Rue Rewards".into(),
            program_name_ar: Some(Some("مكافآت رو".into())),
            ..Default::default()
        };
        assert_eq!(programme_view(&s, "ar").program_name, "مكافآت رو");
        assert_eq!(programme_view(&s, "en").program_name, "Rue Rewards");
        // A stamp card counts orders, and says so before anyone is scanned.
        assert_eq!(programme_view(&s, "en").balance_label, "orders");
    }

    #[test]
    fn an_untranslated_name_still_shows_in_arabic() {
        let s = madar_api::models::LoyaltySettings {
            program_name: "Rue Rewards".into(),
            program_name_ar: Some(None),
            ..Default::default()
        };
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
            track_rewards: vec![],
            birthday_gift: None,
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
            in_combo: false,
            in_deal: false,
        }
    }

    fn pick(line: u32, units: i32) -> RewardPick {
        RewardPick { line, units, track: 1 }
    }

    /// C7: a combo's items earn stamps (the server's), but no reward is taken
    /// inside a combo; a line in a deal is already discounted. The board says
    /// why, in the till's language, and trims a pick asked for on either.
    #[test]
    fn no_reward_inside_a_combo_or_a_deal() {
        let mut combo = line("latte", 1, 17_500);
        combo.in_combo = true;
        let mut dealt = line("latte", 2, 11_000);
        dealt.in_deal = true;
        let plain = line("latte", 1, 5_000);
        let lines = [combo, dealt, plain];
        let b = reward_board(
            &lines,
            &scan(20, None, true),
            &[pick(0, 1), pick(1, 1), pick(2, 1)],
            "en",
        );
        assert_eq!(b.picks, vec![pick(2, 1)], "only the plain line is covered");
        assert!(!b.lines[0].claimable && !b.lines[1].claimable && b.lines[2].claimable);
        assert_eq!(
            b.lines[0].blocked_reason.as_deref(),
            Some("Rewards can't be used inside a combo.")
        );
        assert_eq!(
            b.lines[1].blocked_reason.as_deref(),
            Some("This item is in a deal, so it can't also be a reward.")
        );
        assert!(b.adjusted_reason.is_some(), "the teller hears the trim");
        let ar = reward_board(&lines, &scan(20, None, true), &[], "ar");
        assert_eq!(
            ar.lines[0].blocked_reason.as_deref(),
            Some("لا يمكن استخدام المكافآت داخل الكومبو.")
        );
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
                    in_combo: l.in_combo,
                    in_deal: false,
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

    // ── stamp tracks ─────────────────────────────────────────────────────────

    fn api_track(pos: u32, en: &str, ar: &str, size: i32, balance: i32) -> madar_api::models::MemberTrack {
        let card = madar_loyalty::card::card(balance, size);
        madar_api::models::MemberTrack::new(
            balance,
            card.can_redeem,
            ar.into(),
            en.into(),
            card.points_to_next_reward,
            pos,
            card.progress_to_next,
            card.rewards_ready,
            size,
        )
    }

    fn api_reward(item: &str, cost: i32) -> madar_api::models::RewardItem {
        madar_api::models::RewardItem {
            menu_item_id: uuid::Uuid::parse_str(item).unwrap(),
            name: item.into(),
            base_price: 5_000,
            cost_currency: "visits".into(),
            cost_amount: cost,
            ..Default::default()
        }
    }

    const LATTE: &str = "00000000-0000-0000-0000-00000000000a";
    const SANDWICH: &str = "00000000-0000-0000-0000-00000000000b";
    const CAKE: &str = "00000000-0000-0000-0000-00000000000c";

    /// Track 1 (unnamed, size 5, balance 5: latte), Sandwiches (size 6,
    /// balance 7: sandwich, cake), Cakes (size 4, balance 4: cake).
    fn three_tracks(locale: &str, cap: Option<i32>) -> LoyaltyScanView {
        let mut m = member("Ali", 5, 5);
        m.tracks = Some(Some(vec![
            api_track(1, "", "", 5, 5),
            api_track(2, "Sandwiches", "ساندويتشات", 6, 7),
            api_track(3, "Cakes", "كيك", 4, 4),
        ]));
        let s = madar_api::models::ScanResult {
            member: Box::new(m),
            rewards: vec![api_reward(LATTE, 5)],
            max_rewards_per_order: Some(cap),
            track_rewards: Some(Some(vec![
                madar_api::models::TrackRewards::new(2, vec![api_reward(SANDWICH, 6), api_reward(CAKE, 6)]),
                madar_api::models::TrackRewards::new(3, vec![api_reward(CAKE, 4)]),
            ])),
            ..Default::default()
        };
        scan_view(&s, locale)
    }

    fn basket() -> Vec<RewardLineInput> {
        [line(LATTE, 1, 5_000), line(SANDWICH, 1, 8_000), line(CAKE, 1, 6_000)]
            .into_iter()
            .enumerate()
            .map(|(i, mut l)| {
                l.cart_index = Some(i as u32);
                l
            })
            .collect()
    }

    #[test]
    fn a_one_track_card_has_no_tracks_and_an_older_server_none_either() {
        let mut m = member("Ali", 3, 5);
        assert!(member_view(&m, "en").tracks.is_empty(), "older server");
        m.tracks = Some(Some(vec![api_track(1, "", "", 5, 3)]));
        assert!(member_view(&m, "en").tracks.is_empty(), "one track = today's card");
        let s = scan(10, None, false);
        assert!(s.track_rewards.is_empty());
    }

    #[test]
    fn a_member_shows_each_track_in_the_tills_language() {
        let en = three_tracks("en", None);
        let names: Vec<_> = en.member.tracks.iter().map(|t| t.name.as_str()).collect();
        assert_eq!(names, ["orders", "Sandwiches", "Cakes"], "track 1 unnamed reads as its unit");
        let ar = three_tracks("ar", None);
        assert_eq!(ar.member.tracks[1].name, "ساندويتشات");
        // size 6, balance 7: one ready, one towards the next.
        assert_eq!((en.member.tracks[1].rewards_ready, en.member.tracks[1].balance), (1, 7));
        assert_eq!(en.track_rewards.len(), 2);
        assert_eq!(en.track_rewards[0].rewards[0].cost_label, "6 stamps");
        assert_eq!(en.rewards.len(), 1, "rewards stays track 1's");
    }

    #[test]
    fn each_line_offers_the_tracks_that_can_pay_and_two_ask() {
        let s = three_tracks("en", None);
        let b = reward_board(&basket(), &s, &[], "en");
        assert_eq!(b.lines[0].track_choices, vec![1]);
        assert_eq!(b.lines[0].cost_label, "5 orders");
        assert_eq!(b.lines[1].track_choices, vec![2]);
        assert_eq!(b.lines[1].cost_label, "6 stamps · Sandwiches");
        assert_eq!(b.lines[2].track_choices, vec![2, 3], "the cake: two cards could pay");
        assert_eq!(b.lines[2].cost_label, "6 stamps · Sandwiches / 4 stamps · Cakes");
        // One choice: the tap uses it. Two: the tap does nothing, the till asks.
        let one = toggle_reward(&basket(), &s, &[], 1, "en");
        assert_eq!(one, vec![RewardPick { line: 1, units: 1, track: 2 }]);
        assert!(toggle_reward(&basket(), &s, &[], 2, "en").is_empty(), "nothing preselected");
        let asked = toggle_reward_on_track(&basket(), &s, &[], 2, 3, "en");
        assert_eq!(asked, vec![RewardPick { line: 2, units: 1, track: 3 }]);
        // Once the sandwich spent Sandwiches down to 1, only Cakes can pay.
        let b = reward_board(&basket(), &s, &one, "en");
        assert_eq!(b.lines[2].track_choices, vec![3]);
        // A track that cannot pay is not an answer.
        assert_eq!(toggle_reward_on_track(&basket(), &s, &one, 0, 3, "en"), one);
    }

    #[test]
    fn a_mixed_basket_spends_each_tracks_own_balance() {
        let s = three_tracks("en", None);
        let picks = [
            RewardPick { line: 0, units: 1, track: 1 },
            RewardPick { line: 1, units: 1, track: 2 },
            RewardPick { line: 2, units: 1, track: 3 },
        ];
        let b = reward_board(&basket(), &s, &picks, "en");
        assert_eq!(b.picks, picks.to_vec());
        assert_eq!(b.covered_minor, 19_000, "5,000 + 8,000 + 6,000");
        assert_eq!(b.cost, 15, "5 + 6 + 4");
        assert_eq!(b.balance_after, 0, "track 1: 5 - 5");
        let after: Vec<_> = b.tracks_after.iter().map(|t| (t.position, t.balance_after)).collect();
        assert_eq!(after, [(1, 0), (2, 1), (3, 0)]);
        assert_eq!(b.lines[2].track, 3);
        assert_eq!(b.lines[2].cost_label, "4 stamps · Cakes");
        assert!(b.adjusted_reason.is_none());
        // The redemptions name tracks 2-4 only; track 1 says nothing.
        let r = redemptions_from_picks(&basket(), &b.picks);
        assert_eq!(r.iter().map(|x| x.track).collect::<Vec<_>>(), [None, Some(2), Some(3)]);
        assert_eq!(picks_from_redemptions(&basket(), &r), picks.to_vec());
    }

    #[test]
    fn the_shared_cap_and_a_short_track_trim_and_say_why() {
        let capped = three_tracks("en", Some(2));
        let picks = [
            RewardPick { line: 0, units: 1, track: 1 },
            RewardPick { line: 1, units: 1, track: 2 },
            RewardPick { line: 2, units: 1, track: 3 },
        ];
        let b = reward_board(&basket(), &capped, &picks, "en");
        assert_eq!(b.picks, picks[..2].to_vec(), "one cap across all tracks");
        assert_eq!(b.adjusted_reason.as_deref(), Some("Up to 2 rewards per order here"));
        // Sandwich and cake both on Sandwiches: 12 against a balance of 7.
        let s = three_tracks("en", None);
        let short = reward_board(
            &basket(),
            &s,
            &[RewardPick { line: 1, units: 1, track: 2 }, RewardPick { line: 2, units: 1, track: 2 }],
            "en",
        );
        assert_eq!(short.picks, vec![RewardPick { line: 1, units: 1, track: 2 }]);
        assert_eq!(short.adjusted_reason.as_deref(), Some("Not enough on the card for another"));
        // The cake can still go on Cakes, and only there.
        assert_eq!(short.lines[2].track_choices, vec![3]);
    }

    #[test]
    fn an_award_names_what_each_track_earned() {
        let mut m = member("Sara", 3, 5);
        m.tracks = Some(Some(vec![api_track(1, "", "", 5, 3), api_track(2, "Sandwiches", "ساندويتشات", 6, 2)]));
        let mut r = madar_api::models::AwardResult::new(false, m, Default::default(), 1);
        r.tracks = Some(Some(vec![madar_api::models::TrackAward::new(2, 2)]));
        let out = award_outcome("en", &r);
        let got: Vec<_> = out.tracks.iter().map(|t| (t.name.as_str(), t.awarded, t.balance, t.size)).collect();
        assert_eq!(got, [("orders", 1, 3, 5), ("Sandwiches", 2, 2, 6)]);
        assert_eq!(out.detail, "Sara — 3 orders · 3 / 5", "the detail stays track 1's");
        assert!(award_outcome("en", &result(1, false)).tracks.is_empty());
    }


    /// madar-loyalty's track vectors (the planner the server judges a sale
    /// with) through this till's board: the same picks, cost, units and
    /// trimming; and, before anything is ticked, the same choices per line.
    #[test]
    fn the_board_plans_tracks_as_the_shared_planner_does() {
        use madar_loyalty::tracks::{TrackAsk, TrackProgramme, TracksPlan};
        let v: serde_json::Value = serde_json::from_str(madar_loyalty::vectors::TRACKS).unwrap();
        let mut checked = 0;
        for c in v["cases"].as_array().unwrap() {
            let name = c["name"].as_str().unwrap();
            let lines: Vec<madar_loyalty::Line> = serde_json::from_value(c["lines"].clone()).unwrap();
            let progs: Vec<TrackProgramme> = serde_json::from_value(c["programmes"].clone()).unwrap();
            let asks: Vec<TrackAsk> = serde_json::from_value(c["asks"].clone()).unwrap();
            let Ok(want) = serde_json::from_value::<TracksPlan>(c["till"]["Ok"].clone()) else {
                continue;
            };
            let input: Vec<RewardLineInput> = lines
                .iter()
                .map(|l| RewardLineInput {
                    name: "line".into(),
                    cart_index: None,
                    ticket_line_id: None,
                    menu_item_id: l.menu_item_id.clone(),
                    qty: l.quantity as i32,
                    line_total_minor: 1_000 * l.quantity,
                    is_staff_drink: l.is_staff_drink,
                    in_combo: l.in_combo,
                    in_deal: false,
                })
                .collect();
            let p1 = progs.iter().find(|p| p.track == 1).map(|p| p.programme.clone()).unwrap_or_default();
            let mut sc = scan(0, c["max_per_order"].as_i64(), p1.any_item);
            sc.member.balance = p1.balance;
            sc.any_item_cost = p1.any_item_cost;
            let rv = |r: &madar_loyalty::Reward| LoyaltyRewardView {
                menu_item_id: r.menu_item_id.clone(),
                name: "reward".into(),
                price_minor: 0,
                cost_currency: "visits".into(),
                cost_amount: r.cost,
                cost_label: String::new(),
            };
            sc.rewards = p1.rewards.iter().map(rv).collect();
            // Every track the case names is on the card (track 1 always).
            let mut positions: Vec<u8> = progs.iter().map(|p| p.track).collect();
            positions.extend(asks.iter().map(TrackAsk::track));
            positions.push(1);
            positions.sort_unstable();
            positions.dedup();
            sc.member.tracks = positions
                .iter()
                .map(|&t| LoyaltyTrackView {
                    position: u32::from(t),
                    name: format!("t{t}"),
                    size: 1,
                    balance: progs.iter().find(|p| p.track == t).map_or(0, |p| p.programme.balance),
                    rewards_ready: 0,
                    colour: None,
                })
                .collect();
            sc.track_rewards = progs
                .iter()
                .filter(|p| p.track > 1)
                .map(|p| LoyaltyTrackRewardsView {
                    position: u32::from(p.track),
                    rewards: p.programme.rewards.iter().map(rv).collect(),
                })
                .collect();
            let asked: Vec<RewardPick> = asks
                .iter()
                .map(|a| RewardPick {
                    line: a.line.unwrap() as u32,
                    units: a.units.unwrap_or(1) as i32,
                    track: u32::from(a.track()),
                })
                .collect();
            let b = reward_board(&input, &sc, &asked, "en");
            let mut got: Vec<(usize, i64, u8)> = b.picks.iter().map(|p| (p.line as usize, i64::from(p.units), p.track as u8)).collect();
            let mut exp: Vec<(usize, i64, u8)> = want
                .tracks
                .iter()
                .flat_map(|t| t.plan.lines.iter().map(move |l| (l.line, l.units, t.track)))
                .collect();
            got.sort_unstable();
            exp.sort_unstable();
            assert_eq!(got, exp, "{name}");
            assert_eq!(b.cost, want.tracks.iter().map(|t| t.plan.cost).sum::<i64>(), "{name}");
            assert_eq!(i64::from(b.units_claimed), want.units, "{name}");
            assert_eq!(b.adjusted_reason.is_some(), want.trimmed.is_some(), "{name}");
            if asks.is_empty() {
                let choices: Vec<Vec<u32>> = serde_json::from_value(c["choices"].clone()).unwrap();
                let mine: Vec<Vec<u32>> = b.lines.iter().map(|l| l.track_choices.clone()).collect();
                assert_eq!(mine, choices, "{name}: choices");
            }
            checked += 1;
        }
        assert!(checked >= 8, "checked {checked}");
    }


    // ── the birthday gift ────────────────────────────────────────────────────

    fn api_gift(status: &str, until: &str) -> madar_api::models::BirthdayGiftView {
        madar_api::models::BirthdayGiftView::new(status.into(), until.parse().unwrap())
    }

    #[test]
    fn a_gift_is_open_until_its_last_day_and_names_it() {
        let now = "2026-11-10T12:00:00+02:00".parse().unwrap();
        // Ends at midnight (shop time) after 21 Nov: the last day is the 21st.
        let g = gift_view(&api_gift("open", "2026-11-22T00:00:00+02:00"), now, "en");
        assert!(g.open);
        assert_eq!(g.until_label, "21 Nov");
        assert_eq!(gift_view(&api_gift("open", "2026-11-21T23:59:59+02:00"), now, "ar").until_label, "21 نوفمبر");
        assert!(!gift_view(&api_gift("claimed", "2026-11-22T00:00:00+02:00"), now, "en").open);
        assert!(!gift_view(&api_gift("open", "2026-11-10T11:59:00+02:00"), now, "en").open, "past its window");
    }

    fn with_gift(any_item: bool) -> LoyaltyScanView {
        let mut s = scan(2, None, any_item);
        s.birthday_gift = Some(LoyaltyGiftView {
            open: true,
            valid_until: "2026-11-22T00:00:00+02:00".into(),
            until_label: "21 Nov".into(),
            any_item: None,
            reward_item_ids: None,
        });
        s
    }

    #[test]
    fn the_gift_goes_on_one_reward_line_never_a_staff_drink_combo_deal_or_a_reward() {
        let mut staff = line("latte", 1, 5_000);
        staff.is_staff_drink = true;
        let mut combo = line("latte", 1, 5_000);
        combo.in_combo = true;
        let mut dealt = line("latte", 1, 5_000);
        dealt.in_deal = true;
        let lines = [line("latte", 2, 10_000), line("cake", 1, 9_000), staff, combo, dealt];
        // Catalogue only: the latte; the cake is not a reward here.
        let b = gift_board(&lines, &with_gift(false), &[], None, "en");
        assert!(b.open);
        assert_eq!(b.eligible, vec![0]);
        assert_eq!(b.line, None, "never picked for the teller");
        assert_eq!(b.headline, "Birthday gift: one free item · until 21 Nov");
        // Any item: the cake too.
        let any = gift_board(&lines, &with_gift(true), &[], Some(1), "en");
        assert_eq!(any.eligible, vec![0, 1]);
        assert_eq!(any.line, Some(1));
        assert_eq!(any.covered_minor, 9_000);
        // A line a reward covers cannot also be the gift (balance 2 < 5, so
        // give the member enough for the latte reward first).
        let mut rich = with_gift(false);
        rich.member.balance = 10;
        let taken = gift_board(&lines, &rich, &[pick(0, 1)], Some(0), "en");
        assert!(taken.eligible.is_empty());
        assert_eq!(taken.line, None, "the reward won the line");
        assert_eq!(taken.note.as_deref(), Some("Nothing on this sale can be the gift"));
        // One unit of a two-latte line.
        assert_eq!(gift_board(&lines, &with_gift(false), &[], Some(0), "en").covered_minor, 5_000);
    }

    #[test]
    fn no_gift_or_an_older_server_shows_no_section() {
        let lines = [line("latte", 1, 5_000)];
        let b = gift_board(&lines, &scan(2, None, true), &[], Some(0), "en");
        assert!(!b.open && b.eligible.is_empty() && b.line.is_none());
        let s = madar_api::models::ScanResult::default();
        assert!(scan_view(&s, "en").birthday_gift.is_none());
    }

    #[test]
    fn the_gift_and_a_track_reward_are_named_on_the_receipt() {
        assert_eq!(cover_label(1, None, true, "en"), "Birthday gift");
        assert_eq!(cover_label(1, None, true, "ar"), "هدية عيد الميلاد");
        assert_eq!(cover_label(2, Some("Cakes"), false, "en"), "Reward ×2 · Cakes");
        assert_eq!(cover_label(1, None, false, "en"), "Reward");
        let r = gift_redemption(&[line("latte", 1, 5_000)], 0).unwrap();
        assert!(r.gift && r.units == 1 && r.track.is_none());
        assert!(gift_redemption(&[], 0).is_none());
        // A gift in the asked list is not a reward pick.
        assert!(picks_from_redemptions(&[line("latte", 1, 5_000)], &[r]).is_empty());
    }


    /// The real backend's answers (tool/old_client_api_check/loyalty_tracks)
    /// read by THIS build: three tracks, and an open birthday gift.
    #[test]
    fn the_backends_captures_read_as_tracks_and_a_gift() {
        let three: madar_api::models::ScanResult = serde_json::from_str(include_str!(
            "../../../../tool/old_client_api_check/loyalty_tracks/scan_result.json"
        ))
        .unwrap();
        let v = scan_view(&three, "en");
        assert_eq!(v.member.tracks.len(), 3);
        assert_eq!(v.member.tracks[0].balance, v.member.balance, "track 1 is the card");
        assert_eq!(v.track_rewards.iter().map(|t| t.position).collect::<Vec<_>>(), [2, 3]);
        let gift: madar_api::models::ScanResult = serde_json::from_str(include_str!(
            "../../../../tool/old_client_api_check/loyalty_tracks/gift_scan_result.json"
        ))
        .unwrap();
        let g = gift_view(
            gift.birthday_gift.clone().flatten().as_deref().unwrap(),
            "2026-11-01T10:00:00+02:00".parse().unwrap(),
            "en",
        );
        // Valid until 22:00Z on the 22nd = midnight in Cairo: the 22nd is the last day.
        assert!(g.open);
        assert_eq!(g.until_label, "22 Nov");
        assert!(scan_view(&gift, "en").member.tracks.is_empty());
    }


    /// The lookup's whole catalogue (api v1.24.0+) decides the gift's lines,
    /// whatever the balance; an older server's `rewards` (what the balance
    /// affords) is the fallback.
    #[test]
    fn the_gift_reads_the_whole_catalogue_from_the_lookup() {
        let lines = [line("latte", 1, 5_000), line("cake", 1, 9_000), line("tea", 1, 2_000)];
        // Balance 2: `rewards` lists nothing the member can afford.
        let mut s = with_gift(false);
        s.rewards.clear();
        assert!(gift_board(&lines, &s, &[], None, "en").eligible.is_empty(), "older server");
        let g = s.birthday_gift.as_mut().unwrap();
        g.reward_item_ids = Some(vec!["latte".into(), "cake".into()]);
        g.any_item = Some(false);
        assert_eq!(gift_board(&lines, &s, &[], None, "en").eligible, vec![0, 1]);
        s.birthday_gift.as_mut().unwrap().any_item = Some(true);
        assert_eq!(gift_board(&lines, &s, &[], None, "en").eligible, vec![0, 1, 2]);
        // The check before Charge says the same.
        assert_eq!(gift_check(&lines, &s, Some(2), &[]), Ok(()));
        s.birthday_gift.as_mut().unwrap().any_item = Some(false);
        assert_eq!(gift_check(&lines, &s, Some(2), &[]), Err("loyalty.gift_not_eligible"));
        assert_eq!(gift_check(&lines, &s, Some(0), &[0]), Err("loyalty.gift_not_eligible"), "a reward's line");
        s.birthday_gift.as_mut().unwrap().open = false;
        assert_eq!(gift_check(&lines, &s, Some(0), &[]), Err("loyalty.gift_gone"));
    }

    /// madar-shared's gift vectors (the rule the server claims with) through
    /// the till: the same eligible lines, the same verdict on the chosen one.
    #[test]
    fn the_gift_follows_the_shared_vectors() {
        let v: serde_json::Value = serde_json::from_str(madar_loyalty::vectors::GIFT).unwrap();
        let mut checked = 0;
        for c in v["cases"].as_array().unwrap() {
            let name = c["name"].as_str().unwrap_or("case");
            let lines: Vec<madar_loyalty::Line> = serde_json::from_value(c["lines"].clone()).unwrap();
            let p: madar_loyalty::GiftProgramme = serde_json::from_value(c["programme"].clone()).unwrap();
            let chosen: Option<usize> = serde_json::from_value(c["chosen"].clone()).unwrap();
            let rewarded: Vec<usize> = serde_json::from_value(c["rewarded"].clone()).unwrap();
            let input: Vec<RewardLineInput> = lines
                .iter()
                .map(|l| RewardLineInput {
                    name: "line".into(),
                    cart_index: None,
                    ticket_line_id: None,
                    menu_item_id: l.menu_item_id.clone(),
                    qty: l.quantity as i32,
                    line_total_minor: 1_000 * l.quantity.max(0),
                    is_staff_drink: l.is_staff_drink,
                    in_combo: l.in_combo,
                    in_deal: false,
                })
                .collect();
            let mut sc = with_gift(false);
            let g = sc.birthday_gift.as_mut().unwrap();
            g.open = p.open;
            g.any_item = Some(p.any_item);
            g.reward_item_ids = Some(p.reward_items.clone());
            let want: Vec<u32> = c["eligible"]
                .as_array()
                .unwrap()
                .iter()
                .enumerate()
                .filter(|(_, e)| e.as_bool() == Some(true))
                .map(|(i, _)| i as u32)
                .collect();
            assert_eq!(gift_eligible_lines(&input, &sc, &rewarded), want, "{name}: eligible");
            let got = gift_check(&input, &sc, chosen, &rewarded);
            let want = match c["result"]["refused"].as_str() {
                None => Ok(()),
                Some("LOYALTY_GIFT_NONE") => Err("loyalty.gift_gone"),
                Some(_) => Err("loyalty.gift_not_eligible"),
            };
            assert_eq!(got, want, "{name}: verdict");
            checked += 1;
        }
        assert!(checked >= 5, "checked {checked}");
    }

}
