# CashMovement

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**client_ref** | Option<**uuid::Uuid**> | Client-minted idempotency / reconciliation key, echoed back so an offline client can map its queued movement to the server row. NULL for live online movements. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**moved_by** | **uuid::Uuid** |  | 
**moved_by_name** | **String** |  | 
**note** | **String** |  | 
**shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


