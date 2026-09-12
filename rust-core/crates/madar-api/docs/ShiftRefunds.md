# ShiftRefunds

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**refund_count** | **i64** |  | 
**refunded_amount** | **i64** |  | 
**refunded_cash** | **i64** | The cash slice of `refunded_amount` — what left a drawer. | 
**refunds** | [**Vec<models::RefundFull>**](RefundFull.md) |  | 
**shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


