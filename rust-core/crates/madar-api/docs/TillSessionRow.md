# TillSessionRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_code** | **String** | The branch's short code, the prefix of its order references. | 
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**business_date** | **chrono::NaiveDate** | The branch-local calendar day the till was OPENED on — a till opened at 23:50 and closed at 02:10 belongs to the day it opened, which is the day the takings are reported under. | 
**cash_adjustments** | **i64** | Corrections that name no movement of the three kinds above. Signed: positive = cash the drawer gained. The till report's `cash_adjustments`. | 
**cash_discrepancy** | Option<**i64**> | Declared − expected. Negative = short, positive = over. | [optional]
**cash_drops** | **i64** | Cash moved to the safe, net of corrections to safe drops. Positive = the magnitude that left. | 
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**closing_cash_declared** | Option<**i64**> | What was counted at close. `null` while the till is open, and for a force-close nobody counted. | [optional]
**closing_cash_system** | Option<**i64**> | What the system expected at close. `null` while the till is open. | [optional]
**net_cash_payment** | **i64** | Cash that came in over the counter: cash payments and cash tips on tendered sales, less cash handed back as refunds from this drawer. | 
**net_sales** | **i64** | Those sales' value, net of what refunds took back (`net_sales` in the POS metrics report, `revenue` in the teller report). | 
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opening_cash** | **i64** |  | 
**orders_count** | **i64** | Sales rung on this till, voided and fully-refunded bills excluded — the same count the teller report uses. | 
**pay_ins** | **i64** | Cash added to the drawer that is not a sale (a float top-up), net of corrections to pay-ins. | 
**pay_outs** | **i64** | Cash spent out of the drawer, net of corrections to pay-outs. Positive = the magnitude that left. | 
**status** | **String** | `open` | `closed` | `force_closed`. | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**till_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


