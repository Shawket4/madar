# PublicBookingView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**can_modify** | **bool** | Still confirmed and further away than the branch's lead time. | 
**ends_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**guest_name** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**manage_token** | **String** |  | 
**notes** | Option<**String**> |  | [optional]
**party_size** | **i32** |  | 
**starts_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**status** | **String** |  | 
**timezone** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


