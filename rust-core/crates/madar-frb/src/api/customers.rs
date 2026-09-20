//! Manual customers on the till (phase 6). Pure delegation to madar-core;
//! owns the `CustomerView` mirror.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::customers::CustomerView;

/// A customer as the till shows it.
#[frb(mirror(CustomerView))]
pub struct _CustomerView {
    pub id: String,
    pub name: String,
    /// `None` without `customers.view`, or when there is no phone.
    pub phone: Option<String>,
    /// Masked for someone who may not see the phone, e.g. `•••• 4567`.
    pub phone_hint: Option<String>,
    /// The id their loyalty lives under, when they are a member (`id` itself
    /// under the shared key). `Some` means "offer their loyalty".
    pub loyalty_customer_id: Option<String>,
    /// Added on this till and not yet confirmed by the server.
    pub pending: bool,
    /// A loyalty member.
    pub is_member: bool,
    /// The balance the feed last carried, in words ("120 points"). A hint for
    /// the picker; spending goes through a live lookup.
    pub balance_label: Option<String>,
    /// Where the customer first came from (`pos`, `online`, `loyalty`, …).
    pub source: Option<String>,
}

impl MadarBridge {
    /// Customers matching a name or phone digits, best first. Offline.
    #[frb(sync)]
    pub fn search_customers(&self, query: String) -> Result<Vec<CustomerView>, MadarError> {
        self.inner.search_customers(query).map_err(MadarError::from)
    }

    /// One customer from the till's list.
    #[frb(sync)]
    pub fn customer_by_id(&self, id: String) -> Result<Option<CustomerView>, MadarError> {
        self.inner.customer_by_id(id).map_err(MadarError::from)
    }

    /// Add a customer; usable at once, synced through the queue.
    #[frb(sync)]
    pub fn create_customer(
        &self,
        name: String,
        phone: Option<String>,
    ) -> Result<CustomerView, MadarError> {
        self.inner.create_customer(name, phone).map_err(MadarError::from)
    }

    /// The customer a scanned loyalty member IS, from the till's list — so a
    /// scan attaches the person, not just a balance. `None` when the list does
    /// not hold them.
    #[frb(sync)]
    pub fn customer_for_member(&self, member_id: String) -> Result<Option<CustomerView>, MadarError> {
        self.inner.customer_for_member(member_id).map_err(MadarError::from)
    }

    /// Attach a customer to a sale already rung (a settled bill by its ticket
    /// id, a finalized online order, a sale in the history), or take them off
    /// with `None`. Offline: queued behind the sale. True while still queued.
    #[frb(sync)]
    pub fn attach_customer(&self, order_id: String, customer_id: Option<String>) -> Result<bool, MadarError> {
        self.inner.attach_customer(order_id, customer_id).map_err(MadarError::from)
    }

    /// The customer on a rung sale, by any of its ids. Offline.
    #[frb(sync)]
    pub fn order_customer(&self, order_id: String) -> Result<Option<CustomerView>, MadarError> {
        self.inner.order_customer(order_id).map_err(MadarError::from)
    }
}
