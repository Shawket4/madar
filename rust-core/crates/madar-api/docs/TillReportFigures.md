# TillReportFigures

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

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


