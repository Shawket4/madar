//! The teller's loyalty scan — FRB delegation over `madar_core::MadarCore` plus
//! the view mirrors. Binding code only.
//!
//! Nothing here decides anything. The UI scans a barcode (or types a phone) and
//! renders what the core returns; a sale's points are computed by the SERVER
//! from the order's own totals when it settles, not by the till.

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use flutter_rust_bridge::frb;

pub use madar_core::loyalty::{
    LoyaltyAwardOutcome, LoyaltyLedgerView, LoyaltyMemberView, LoyaltyProgrammeView,
    LoyaltyRewardView, LoyaltyScanInput, LoyaltyScanView,
};

/// The branch's programme, as the till needs it. Three facts, not the
/// dashboard's forty — everything else on the settings decides what the SERVER
/// does when a sale settles.
#[frb(mirror(LoyaltyProgrammeView))]
pub struct _LoyaltyProgrammeView {
    /// Is a programme running here at all? `false` keeps every loyalty control
    /// off the screen rather than offering a card that cannot exist.
    pub enabled: bool,
    /// `points` (earned on spend) or `visits` (a stamp an order).
    pub mode: String,
    /// What the shop calls it, in the till's language.
    pub program_name: String,
    /// The customer's word for what it collects — "points" / "orders".
    pub balance_label: String,
}

/// What a captured string is. The UI captures bytes — camera frames via the
/// platform decoder, USB-wedge keystrokes via the OS text path, both of which
/// Rust cannot reach without re-implementing the platform camera stack — but it
/// does not decide what they MEAN. That is [`MadarBridge::classify_loyalty_input`].
#[frb(mirror(LoyaltyScanInput))]
pub struct _LoyaltyScanInput {
    /// `token` | `phone` | `partial`.
    pub kind: String,
    /// The cleaned value to look up. Empty while `partial`.
    pub value: String,
}

/// A member as the scan screen shows them.
#[frb(mirror(LoyaltyMemberView))]
pub struct _LoyaltyMemberView {
    pub id: String,
    pub name: String,
    pub phone: String,
    /// `points` or `visits` — what this branch collects. Never both.
    pub mode: String,
    /// The live balance, in `mode`'s currency.
    pub balance: i64,
    /// The cheapest reward on offer here, in the same currency.
    pub next_reward_cost: i64,
    /// Rewards ALREADY earned and unclaimed. A card does not stop at full: six
    /// orders against a five-order reward is one earned and one towards the
    /// next, and a customer owed two may claim both on one bill.
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

/// One reward the member could claim right now. Empty until they can — the
/// screen must not offer what has not been earned.
#[frb(mirror(LoyaltyRewardView))]
pub struct _LoyaltyRewardView {
    pub menu_item_id: String,
    pub name: String,
    pub price_minor: i64,
    /// `points` or `visits`.
    pub cost_currency: String,
    pub cost_amount: i64,
    /// Ready-made ("5 orders"), so the UI formats no numbers.
    pub cost_label: String,
}

/// One line of the member's recent history, already phrased for display.
#[frb(mirror(LoyaltyLedgerView))]
pub struct _LoyaltyLedgerView {
    /// `earn` | `redeem` | `adjust`.
    pub kind: String,
    pub points: i64,
    /// Already signed for display ("+13", "−100").
    pub points_label: String,
    /// `points` or `visits` — which balance this row moved.
    pub currency: String,
    pub branch_name: Option<String>,
    pub reward_name: Option<String>,
    pub created_at: String,
}

/// Everything one lookup gives the scan screen.
#[frb(mirror(LoyaltyScanView))]
pub struct _LoyaltyScanView {
    pub member: LoyaltyMemberView,
    pub rewards: Vec<LoyaltyRewardView>,
    pub recent: Vec<LoyaltyLedgerView>,
    /// The whole menu is claimable, not only `rewards`. The till then offers
    /// every line at `any_item_cost` rather than only the curated ones.
    pub any_item: bool,
    /// What one line costs when `any_item` is on.
    pub any_item_cost: i64,
}

/// What came of pressing "add points" on a sale.
///
/// Three outcomes a teller must be able to tell apart — added, already
/// collected, queued — decided by the server and phrased by the core, so the
/// sheet renders a sentence rather than choosing one.
#[frb(mirror(LoyaltyAwardOutcome))]
pub struct _LoyaltyAwardOutcome {
    /// Where the customer now stands. `None` only for a queued press: there is
    /// no balance yet, and a made-up one is a lie the customer can read.
    pub member: Option<LoyaltyMemberView>,
    /// The press is queued because this till could not reach the server.
    pub queued: bool,
    /// The sale had already earned. The call is idempotent per order, so the
    /// second press changed nothing and must not claim to have.
    pub already_collected: bool,
    /// What THIS press added. Zero when already collected, and when the sale was
    /// too small to reach one point.
    pub points_awarded: i64,
    /// Ready-made headline, localized.
    pub headline: String,
    /// Ready-made line under it, localized.
    pub detail: String,
}

impl MadarBridge {
    /// Decide what a captured string is: a whole member token, a phone number,
    /// or neither yet.
    ///
    /// Sync and allocation-light, so the scan sheet can call it on EVERY
    /// keystroke. That is what makes a cheap USB imager work with no setup:
    /// many wedge scanners type their payload and never send Enter, so the
    /// sheet fires the lookup the moment this says the buffer is a whole card.
    /// The token's shape lives in the core beside the server's own, not in Dart.
    #[frb(sync)]
    pub fn classify_loyalty_input(&self, raw: String) -> LoyaltyScanInput {
        madar_core::loyalty::classify_scan_input(&raw)
    }

    /// The branch's programme: whether one runs, what it collects, its name.
    /// Cached, so an offline till still knows whether to draw the control.
    pub async fn loyalty_settings(&self) -> Result<LoyaltyProgrammeView, MadarError> {
        self.inner
            .loyalty_settings()
            .await
            .map_err(MadarError::from)
    }

    /// Identify the member in front of the till, from a scanned pass barcode or
    /// (fallback) a phone number.
    ///
    /// Online-only: a balance is shared state any till can move, and a stale
    /// number shown to a customer is worse than asking the teller to reconnect.
    pub async fn loyalty_lookup(
        &self,
        token: Option<String>,
        phone: Option<String>,
    ) -> Result<LoyaltyScanView, MadarError> {
        self.inner
            .loyalty_lookup(token, phone)
            .await
            .map_err(MadarError::from)
    }

    /// Is this sale still inside its 24-hour award window?
    ///
    /// Sync, so a history list can gate every row's button without a round trip.
    /// Both arguments are RFC3339; pass the device's corrected now. This hides a
    /// button the server would refuse — it does not decide anything, because the
    /// server checks the same rule against the order's own timestamp.
    #[frb(sync)]
    pub fn loyalty_award_window_open(&self, order_created_at: String, now: String) -> bool {
        madar_core::loyalty::award_window_open(&order_created_at, &now)
    }

    /// Add a sale's points to a member's balance — the receipt's button, and the
    /// one on a past order in the history.
    ///
    /// Returns the outcome the SERVER reported, already phrased: the points went
    /// on, the sale had already been collected for (the endpoint is idempotent
    /// per order, so a second press is safe and must say so), or the press was
    /// queued because this till could not reach the server.
    ///
    /// `customer_id` is the member already identified for this sale — the card
    /// scanned before payment. Pass it and no second scan is needed; the order
    /// remembers who it was either way, so the server accepts an award with no
    /// member named at all.
    pub async fn loyalty_award(
        &self,
        order_id: Option<String>,
        order_key: Option<String>,
        order_created_at: String,
        token: Option<String>,
        phone: Option<String>,
        customer_id: Option<String>,
    ) -> Result<LoyaltyAwardOutcome, MadarError> {
        self.inner
            .loyalty_award(
                order_id,
                order_key,
                order_created_at,
                token,
                phone,
                customer_id,
            )
            .await
            .map_err(MadarError::from)
    }

    // Redeeming no longer lives here. A reward now covers lines of a cart and
    // changes what is owed, so it rides on the checkout itself
    // (`CheckoutInput::loyalty_redemptions`) — one path to spend a balance, and
    // therefore one place for it to be right.
}
