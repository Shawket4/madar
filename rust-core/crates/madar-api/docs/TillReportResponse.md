# TillReportResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cash_adjustments** | **i64** |  | 
**cash_in_refunded_sales** | Option<**i64**> |  | [optional]
**cash_movements** | [**Vec<models::CashMovementSummaryRow>**](CashMovementSummaryRow.md) |  | 
**cash_movements_in** | **i64** |  | 
**cash_movements_net** | **i64** |  | 
**cash_movements_out** | **i64** |  | 
**cash_tips** | **i64** |  | 
**expected_cash** | **i64** |  | 
**net_payments** | **i64** |  | 
**non_cash_tips** | **i64** |  | 
**payment_summary** | [**Vec<models::PaymentSummaryRow>**](PaymentSummaryRow.md) |  | 
**printed_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**refunds_issued_amount** | Option<**i64**> |  | [optional]
**refunds_issued_cash** | Option<**i64**> |  | [optional]
**refunds_issued_count** | Option<**i64**> |  | [optional]
**safe_drops** | **i64** |  | 
**standard_float** | Option<**i64**> | `branches.standard_float`. | [optional]
**suggested_safe_drop** | Option<**i64**> |  | [optional]
**timezone** | Option<**String**> |  | [optional]
**total_payments** | **i64** |  | 
**total_tips** | **i64** |  | 
**voided_amount** | **i64** |  | 
**as_of_seq** | Option<**i64**> | The branch changefeed horizon read BEFORE the figures (OFFLINE_B_DESIGN §7): every change with `seq <= as_of_seq` is in this report. A device whose cursor has reached it, with nothing of the till still on its way, can take these figures as the authority. `0` when no horizon was available (then it is never newer than any cursor). Additive. | [optional]
**old_bills_at_close** | Option<**i32**> |  | [optional]
**open_bills_at_close** | Option<**i32**> |  | [optional]
**order_number_range** | [**models::OrderNumberRange**](OrderNumberRange.md) |  | 
**reconciliation** | [**Vec<models::TillReconciliationLine>**](TillReconciliationLine.md) |  | 
**till** | [**models::Till**](Till.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


