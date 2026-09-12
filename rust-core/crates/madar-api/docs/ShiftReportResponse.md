# ShiftReportResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cash_adjustments** | **i64** | Signed sum of corrections that reverse nothing on record (a miscounted float). Kept apart so a fix-up is never mistaken for a receipt or a cost. | 
**cash_in_refunded_sales** | Option<**i64**> | Cash tenders and cash tips on this shift's sales that were later FULLY refunded. `payment_summary` and `cash_tips` leave those sales out (they are revenue figures and match the sales report), but the notes did go into the drawer, so `expected_cash` counts them. Reported so the sheet adds up: `expected_cash = opening_cash + cash bucket + cash_tips + cash_in_refunded_sales + cash_movements_net − refunds_issued_cash`. | [optional]
**cash_movements** | [**Vec<models::CashMovementSummaryRow>**](CashMovementSummaryRow.md) |  | 
**cash_movements_in** | **i64** | Non-sale cash placed in the drawer (`pay_in`), net of any correction that reversed one. Positive. | 
**cash_movements_net** | **i64** | Signed net effect of EVERY movement on the drawer — the figure `compute_system_cash` adds to the float and the cash sales: `in − out − safe_drops + cash_adjustments`. | 
**cash_movements_out** | **i64** | What the shift SPENT (`pay_out`), net of corrections. Positive. A safe drop is NOT in here — that money left the drawer but not the shop. | 
**cash_tips** | **i64** | The cash slice of `total_tips` (snapshotted `tip_is_cash`). This IS in the drawer, so it is counted by `expected_cash` even though it is not part of `net_payments`. | 
**expected_cash** | **i64** | Authoritative system (expected) cash in the drawer. For a closed shift this is the snapshot taken at close (`closing_cash_system`); for an open shift it is computed live via the same formula. Clients should display this directly instead of re-deriving it from the payment breakdown. | 
**net_payments** | **i64** |  | 
**non_cash_tips** | **i64** | `total_tips - cash_tips` — tips added onto a card/wallet tender. | 
**payment_summary** | [**Vec<models::PaymentSummaryRow>**](PaymentSummaryRow.md) | Money COLLECTED FOR GOODS, bucketed by the method actually tendered (`order_payments`, so a split order contributes to each leg it really used). Tips are NOT in here — see `total_tips`. | 
**printed_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**refunds_issued_amount** | Option<**i64**> |  | [optional]
**refunds_issued_cash** | Option<**i64**> |  | [optional]
**refunds_issued_count** | Option<**i64**> | Refunds ISSUED FROM THIS DRAWER — keyed on `order_refunds.shift_id`, which need not be the shift that made the sale. Money OUT; the Z-report's returns line. `refunds_issued_cash` is what `compute_system_cash` subtracts. | [optional]
**safe_drops** | **i64** | Cash moved from the drawer to the safe (`safe_drop`), net of corrections. Positive. Out of the drawer, still the shop's. | 
**shift** | [**models::Shift**](Shift.md) |  | 
**standard_float** | Option<**i64**> | The till's standard float, when the shop has set one: what should stay in the drawer at close. `None` means \"not decided\" — propose nothing. | [optional]
**suggested_safe_drop** | Option<**i64**> | For an OPEN shift on a till with a standard float: how much of `expected_cash` to drop into the safe so the drawer closes at the float. Never negative — a drawer under its float has nothing to drop. `None` when the shift is closed or the till has no float. | [optional]
**total_payments** | **i64** |  | 
**total_tips** | **i64** | Tips, as a standalone figure — never folded into a method bucket, and never part of `total_payments`/`net_payments`. Mirrors `total_tips` on the sales reports so the two screens agree on what \"revenue\" means. | 
**voided_amount** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


