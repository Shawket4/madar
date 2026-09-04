# ShiftReportResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cash_movements** | [**Vec<models::CashMovementSummaryRow>**](CashMovementSummaryRow.md) |  | 
**cash_movements_in** | **i64** |  | 
**cash_movements_net** | **i64** | Net of all cash movements (in - out) as a signed integer | 
**cash_movements_out** | **i64** |  | 
**cash_tips** | **i64** | The cash slice of `total_tips` (snapshotted `tip_is_cash`). This IS in the drawer, so it is counted by `expected_cash` even though it is not part of `net_payments`. | 
**expected_cash** | **i64** | Authoritative system (expected) cash in the drawer. For a closed shift this is the snapshot taken at close (`closing_cash_system`); for an open shift it is computed live via the same formula. Clients should display this directly instead of re-deriving it from the payment breakdown. | 
**net_payments** | **i64** |  | 
**non_cash_tips** | **i64** | `total_tips - cash_tips` — tips added onto a card/wallet tender. | 
**payment_summary** | [**Vec<models::PaymentSummaryRow>**](PaymentSummaryRow.md) | Money COLLECTED FOR GOODS, bucketed by the method actually tendered (`order_payments`, so a split order contributes to each leg it really used). Tips are NOT in here — see `total_tips`. | 
**printed_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**shift** | [**models::Shift**](Shift.md) |  | 
**total_payments** | **i64** |  | 
**total_tips** | **i64** | Tips, as a standalone figure — never folded into a method bucket, and never part of `total_payments`/`net_payments`. Mirrors `total_tips` on the sales reports so the two screens agree on what \"revenue\" means. | 
**voided_amount** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


