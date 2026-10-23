//! Three-track loyalty responses (loyalty_tracks/) decoded into THIS release's
//! generated models, the types a released POS (v0.13.0+) decodes them into,
//! and a check that what it reads still means track 1: `member.balance` is
//! track 1's balance and `ScanResult.rewards` offers no track 2-4 item.
#![cfg(any(feature = "v0130", feature = "v0140", feature = "v0171"))]

use madar_api::models;
use serde_json::Value;

fn read(file: &str) -> Value {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/loyalty_tracks");
    serde_json::from_str(&std::fs::read_to_string(format!("{dir}/{file}")).unwrap()).unwrap()
}

fn track_one_balance(member: &Value) -> i64 {
    let tracks = member["tracks"].as_array().expect("a three-track capture");
    assert_eq!(tracks.len(), 3, "the capture is a three-track card");
    tracks.iter().find(|t| t["position"] == 1).unwrap()["balance"].as_i64().unwrap()
}

#[test]
fn three_track_responses_decode_and_keep_track_one() {
    let manifest = read("manifest.json");
    for e in manifest["files"].as_array().unwrap() {
        let (file, model) = (e["file"].as_str().unwrap(), e["model"].as_str().unwrap());
        let v = read(file);
        let r = match model {
            "ScanResult" => serde_json::from_value::<models::ScanResult>(v.clone()).map(|_| ()),
            "AwardResult" => serde_json::from_value::<models::AwardResult>(v.clone()).map(|_| ()),
            "MemberDetail" => serde_json::from_value::<models::MemberDetail>(v.clone()).map(|_| ()),
            "OrderFull" => serde_json::from_value::<models::OrderFull>(v.clone()).map(|_| ()),
            other => panic!("unknown model {other}"),
        };
        r.unwrap_or_else(|err| panic!("{file} as {model}: {err}"));
    }

    // What an old till shows and spends is track 1's.
    let scan = read("scan_result.json");
    let old: models::ScanResult = serde_json::from_value(scan.clone()).unwrap();
    assert_eq!(i64::from(old.member.balance), track_one_balance(&scan["member"]));
    let other_items: Vec<&str> = scan["track_rewards"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|t| t["rewards"].as_array().unwrap())
        .filter_map(|r| r["menu_item_id"].as_str())
        .collect();
    for r in &old.rewards {
        assert!(
            !other_items.contains(&r.menu_item_id.to_string().as_str()),
            "a track 2-4 reward leaked into `rewards`: {}",
            r.menu_item_id
        );
    }
    let award = read("award_result.json");
    let old: models::AwardResult = serde_json::from_value(award.clone()).unwrap();
    assert_eq!(i64::from(old.member.balance), track_one_balance(&award["member"]));
    eprintln!("three-track loyalty responses decode, track 1 unchanged");
}
