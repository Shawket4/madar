# SyncModifierGroup

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**group_id** | **uuid::Uuid** |  | 
**is_required** | **bool** |  | 
**legacy_addon_type** | Option<**String**> |  | [optional]
**max** | Option<**i32**> |  | [optional]
**min** | **i32** |  | 
**name** | **String** | The group's authored display name (custom groups have no legacy type — this is what the POS renders as the section title). | 
**name_translations** | **serde_json::Value** |  | 
**options** | [**Vec<models::SyncOption>**](SyncOption.md) |  | 
**selection_type** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


