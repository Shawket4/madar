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
    pub loyalty_customer_id: Option<String>,
    /// Added on this till and not yet confirmed by the server.
    pub pending: bool,
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
}
