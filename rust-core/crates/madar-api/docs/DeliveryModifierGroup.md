# DeliveryModifierGroup

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addon_type** | Option<**String**> | The group's legacy addon type (`milk_type` / `coffee_type` / `extra` / custom) — the swap-family hint the customizer keys its delta-price estimate on. `None` for groups with no legacy lineage. | [optional]
**group_id** | **uuid::Uuid** |  | 
**is_required** | **bool** |  | 
**max_selections** | Option<**i32**> |  | [optional]
**min_selections** | **i32** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**options** | [**Vec<models::DeliveryModifierOption>**](DeliveryModifierOption.md) |  | 
**selection_type** | **String** | \"single\" | \"multi\". | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


