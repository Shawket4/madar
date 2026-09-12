# RefundIssued

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**branch_id** | **uuid::Uuid** |  | 
**client_ref** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**is_cash** | **bool** | Whether `method` meant cash when the refund was issued. Snapshotted. | 
**issued_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**issued_by** | **uuid::Uuid** |  | 
**issued_by_name** | **String** |  | 
**method** | **String** |  | 
**note** | Option<**String**> |  | [optional]
**order_id** | **uuid::Uuid** |  | 
**reason** | **String** | One of the [`RefundReason`] spellings. | 
**shift_id** | **uuid::Uuid** | The shift the refund was ISSUED in — the drawer the money left. Not necessarily the shift the order was sold in. | 
**lines** | [**Vec<models::RefundLine>**](RefundLine.md) |  | 
**refund_count** | **i64** |  | 
**refunded_amount** | **i64** |  | 
**refunded_cash** | **i64** | The cash slice of `refunded_amount` — what left a drawer. | 
**order_status** | **String** | `orders.status` after this refund — `refunded` only when the cumulative amount reached the total (the trigger's rule, not this module's). | 
**refundable_remaining** | **i64** | `total_amount − refunded_amount`: what may still be returned. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


