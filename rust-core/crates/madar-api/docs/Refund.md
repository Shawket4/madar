# Refund

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

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


