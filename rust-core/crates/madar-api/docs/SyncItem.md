# SyncItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**combo** | Option<[**models::ComboFeed**](ComboFeed.md)> | A kind=combo row: its slots, windows and resolved channel toggles. | [optional]
**id** | **uuid::Uuid** |  | 
**kind** | Option<**String**> | `item` | `combo` (combos module). Additive. | [optional]
**meal** | Option<[**models::MealLink**](MealLink.md)> | A kind=item row: its \"make it a meal\" upsell (C14). | [optional]
**modifier_groups** | [**Vec<models::SyncModifierGroup>**](SyncModifierGroup.md) |  | 
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | 
**sizes** | [**Vec<models::SyncSize>**](SyncSize.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


