//! Deserializes every golden backend response captured under
//! MadarRust/tests/fixtures/legacy_till_api/ into THIS release's generated
//! models — the exact types the old POS core decodes them into. Passing means a
//! field the old client requires is still present with a compatible type.
//!
//! GOLDEN_DIR must point at that fixture directory (the script sets it).

use madar_api::models;
use serde_json::Value;

fn parse(model: &str, v: Value) -> Result<(), String> {
    macro_rules! p {
        ($t:ty) => {
            serde_json::from_value::<$t>(v).map(|_| ()).map_err(|e| e.to_string())
        };
    }
    match model {
        "ShiftPreFill" => p!(models::ShiftPreFill),
        "Shift" => p!(models::Shift),
        "PaginatedShifts" => p!(models::PaginatedShifts),
        "ShiftReportResponse" => p!(models::ShiftReportResponse),
        "CashMovement" => p!(models::CashMovement),
        "Vec<CashMovement>" => p!(Vec<models::CashMovement>),
        "CloseShiftResponse" => p!(models::CloseShiftResponse),
        "Vec<Till>" => p!(Vec<models::Till>),
        "OrderFull" => p!(models::OrderFull),
        "PaginatedOrders" => p!(models::PaginatedOrders),
        "ShiftSummary" => p!(models::ShiftSummary),
        "Order" => p!(models::Order),
        "OpenTicketView" => p!(models::OpenTicketView),
        "Vec<OpenTicketView>" => p!(Vec<models::OpenTicketView>),
        "FinalizeResponse" => p!(models::FinalizeResponse),
        "DeliveryOrder" => p!(models::DeliveryOrder),
        "Vec<DeliveryOrder>" => p!(Vec<models::DeliveryOrder>),
        #[cfg(any(feature = "v060", feature = "v061"))]
        "OrderRefunds" => p!(models::OrderRefunds),
        #[cfg(any(feature = "v060", feature = "v061"))]
        "ShiftRefunds" => p!(models::ShiftRefunds),
        #[cfg(any(feature = "v060", feature = "v061"))]
        "RefundIssued" => p!(models::RefundIssued),
        // The drain only needs a JSON object with a top-level string `id`.
        "ReplayCreateOrderAck" => match v.get("id").and_then(|x| x.as_str()) {
            Some(_) => Ok(()),
            None => Err("no top-level string id".into()),
        },
        other => Err(format!("harness does not know model {other}")),
    }
}

#[test]
fn golden_responses_parse_into_old_models() {
    let dir = std::env::var("GOLDEN_DIR").expect("GOLDEN_DIR not set");
    let manifest: Value =
        serde_json::from_str(&std::fs::read_to_string(format!("{dir}/manifest.json")).unwrap()).unwrap();
    let release = if cfg!(feature = "v051") {
        "v0.5.1"
    } else if cfg!(feature = "v061") {
        "v0.6.1"
    } else {
        "v0.6.0"
    };
    let mut checked = 0;
    let mut failures = vec![];
    for entry in manifest["files"].as_array().unwrap() {
        let clients: Vec<&str> = entry["clients"].as_array().unwrap().iter().filter_map(|c| c.as_str()).collect();
        if !clients.contains(&release) {
            continue;
        }
        let file = entry["file"].as_str().unwrap();
        let model = entry["model"].as_str().unwrap();
        let body: Value = serde_json::from_str(&std::fs::read_to_string(format!("{dir}/{file}")).unwrap())
            .unwrap_or_else(|e| panic!("{file}: not JSON: {e}"));
        // Captures are wrapped: { "request": {...}, "status": N, "body": ... }.
        let payload = body.get("body").cloned().unwrap_or(body);
        if let Err(e) = parse(model, payload) {
            failures.push(format!("{file} as {model}: {e}"));
        }
        checked += 1;
    }
    assert!(checked > 0, "manifest listed nothing for {release}");
    assert!(failures.is_empty(), "{release}: {} failures:\n{}", failures.len(), failures.join("\n"));
    eprintln!("{release}: {checked} golden responses parsed");
}
