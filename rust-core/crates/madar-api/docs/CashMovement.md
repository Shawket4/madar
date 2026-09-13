# CashMovement

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**client_ref** | Option<**uuid::Uuid**> |  | [optional]
**corrects_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**kind** | **String** |  | 
**moved_by** | **uuid::Uuid** |  | 
**moved_by_name** | **String** |  | 
**note** | **String** |  | 
**shift_id** | **uuid::Uuid** | DEPRECATED: same value as `till_id` (kept for POS v0.5.1/v0.6.0). | 
**till_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


