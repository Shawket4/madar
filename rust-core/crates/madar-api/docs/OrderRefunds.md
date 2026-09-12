# OrderRefunds

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**refund_count** | **i64** |  | 
**refunded_amount** | **i64** |  | 
**refunded_cash** | **i64** | The cash slice of `refunded_amount` — what left a drawer. | 
**order_id** | **uuid::Uuid** |  | 
**order_status** | **String** |  | 
**refundable_remaining** | **i64** |  | 
**refunds** | [**Vec<models::RefundFull>**](RefundFull.md) |  | 
**total_amount** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


