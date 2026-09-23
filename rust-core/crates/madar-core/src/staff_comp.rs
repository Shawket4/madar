//! What a staff drink is given for free, and what it still pays for.
//!
//! The RULE (`comp`, `group_allowance`) lives in madar-shared
//! (`madar_money::staff_comp`), the one copy the till and the server run,
//! pinned by its `staff_comp_vectors.json`; see its module note for the owner's
//! rule. The INPUTS are still built here from the till's menu view
//! (`cart.rs`) and on the server from its own.

pub use madar_money::staff_comp::{
    comp, group_allowance, CompBreakdown, CompGroup, CompInput, CompOption, CompPick, CompResult,
    CompSize, GroupComp, PickComp,
};
