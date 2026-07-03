//! `AppRoute` re-declared for FRB (struct variants can't be mirrored).
//! The core alone decides the route; the host renders it.

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AppRoute {
    /// Till not bound to a branch → manager device-setup.
    DeviceSetup,
    /// Configured but signed out → teller/waiter PIN login.
    Login,
    /// Signed in, no open shift → open-shift screen.
    OpenShift,
    /// Signed in with an open shift → order screen.
    Order,
    /// Device run as a kitchen display → the KDS for `station_id` (no shift needed).
    KitchenDisplay { station_id: String },
    /// A signed-in WAITER (holds no shift) → the open-tickets / take-order screen.
    WaiterTickets,
}

impl From<madar_core::AppRoute> for AppRoute {
    fn from(r: madar_core::AppRoute) -> Self {
        match r {
            madar_core::AppRoute::DeviceSetup => Self::DeviceSetup,
            madar_core::AppRoute::Login => Self::Login,
            madar_core::AppRoute::OpenShift => Self::OpenShift,
            madar_core::AppRoute::Order => Self::Order,
            madar_core::AppRoute::KitchenDisplay { station_id } => {
                Self::KitchenDisplay { station_id }
            }
            madar_core::AppRoute::WaiterTickets => Self::WaiterTickets,
        }
    }
}
