# SyncModifierGroup

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**effect** | Option<**String**> | What choosing does: `none` | `adds` | `swaps`. | [optional]
**group_id** | **uuid::Uuid** |  | 
**is_required** | **bool** |  | 
**legacy_addon_type** | Option<**String**> |  | [optional]
**max** | Option<**i32**> |  | [optional]
**min** | **i32** |  | 
**name** | **String** | The group's authored display name (custom groups have no legacy type — this is what the POS renders as the section title). | 
**name_translations** | **serde_json::Value** |  | 
**options** | [**Vec<models::SyncOption>**](SyncOption.md) |  | 
**selection_type** | **String** |  | 
**swap_category_id** | Option<**uuid::Uuid**> | For `swaps`: the ingredient category whose recipe line each option replaces. | [optional]
**swap_category_slug** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


