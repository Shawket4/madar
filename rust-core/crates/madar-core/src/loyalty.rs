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
    let member = member_view(&r.member);
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

/// A member token is `M` + 22 base64url characters — the shape
/// `loyalty::mint_member_token` produces on the server (one v4 UUID's 16 bytes,
/// base64url, unpadded). Pinned here so a half-typed buffer is never mistaken
/// for a whole card.
const TOKEN_LEN: usize = 23;

/// Classify a captured string. Never panics and never allocates on the hot
/// path's common answer (a partial buffer).
pub fn classify_scan_input(raw: &str) -> LoyaltyScanInput {
    let s = raw.trim();
    if s.is_empty() {
        return LoyaltyScanInput::partial();
    }

    // A card: exact length, the `M` sentinel, and a base64url tail.
    if s.len() == TOKEN_LEN
        && s.starts_with('M')
        && s[1..]
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return LoyaltyScanInput::token(s.to_string());
    }

    // A phone: digits once the punctuation people type is removed. The range
    // matches the server's `normalize_phone`, so a number this accepts is a
    // number the lookup can actually use.
    let digits: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
    let only_phone_chars = s
        .chars()
        .all(|c| c.is_ascii_digit() || matches!(c, '+' | ' ' | '-' | '(' | ')'));
    if only_phone_chars && (10..=15).contains(&digits.len()) {
        return LoyaltyScanInput::phone(s.to_string());
    }

    LoyaltyScanInput::partial()
}

/// "30 / 100", or the earned line once the threshold is reached.
pub fn progress_label(balance: i64, threshold: i64) -> String {
    if threshold > 0 && balance >= threshold {
        "Reward earned".to_string()
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
pub fn balance_label(mode: &str) -> &'static str {
    match mode {
        "visits" => "orders",
        _ => "points",
    }
}

pub fn member_view(m: &madar_api::models::MemberView) -> LoyaltyMemberView {
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
        progress_label: progress_label(balance, target),
        balance_label: balance_label(&m.mode).to_string(),
    }
}

pub fn scan_view(s: &madar_api::models::ScanResult) -> LoyaltyScanView {
    LoyaltyScanView {
        member: member_view(&s.member),
        rewards: s
            .rewards
            .iter()
            .map(|r| LoyaltyRewardView {
                menu_item_id: r.menu_item_id.to_string(),
                name: r.name.clone(),
                price_minor: r.base_price as i64,
                cost_currency: r.cost_currency.clone(),
                cost_amount: r.cost_amount as i64,
                cost_label: format!("{} {}", r.cost_amount, balance_label(&r.cost_currency)),
            })
            .collect(),
        any_item: s.any_item,
        any_item_cost: s.any_item_cost as i64,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_counts_down_then_announces() {
        assert_eq!(progress_label(30, 100), "30 / 100");
        assert_eq!(progress_label(100, 100), "Reward earned");
        assert_eq!(progress_label(130, 100), "Reward earned");
    }

    #[test]
    fn a_zero_threshold_does_not_announce_a_reward() {
        // Defensive: the server's column is CHECK (> 0), but a screen telling
        // every customer their reward was ready would be a bad way to find out.
        assert_eq!(progress_label(0, 0), "0 / 0");
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
}
