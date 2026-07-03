# ShiftReportResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cash_movements** | [**Vec<models::CashMovementSummaryRow>**](CashMovementSummaryRow.md) |  | 
**cash_movements_in** | **i64** |  | 
**cash_movements_net** | **i64** | Net of all cash movements (in - out) as a signed integer | 
**cash_movements_out** | **i64** |  | 
**expected_cash** | **i64** | Authoritative system (expected) cash in the drawer. For a closed shift this is the snapshot taken at close (`closing_cash_system`); for an open shift it is computed live via the same formula. Clients should display this directly instead of re-deriving it from the payment breakdown. | 
**net_payments** | **i64** |  | 
**payment_summary** | [**Vec<models::PaymentSummaryRow>**](PaymentSummaryRow.md) |  | 
**printed_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**shift** | [**models::Shift**](Shift.md) |  | 
**total_payments** | **i64** |  | 
**voided_amount** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


