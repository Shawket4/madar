# DeliveryMenuItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**allowed_addon_ids** | **Vec<uuid::Uuid>** | Explicit per-item addon allowlist (IDs from `menu_item_allowed_addons`). When non-empty the customizer filters the global catalog to these IDs by default, with a \"show all\" escape hatch. Empty = no restriction. | 
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**default_milk_addon_id** | Option<**uuid::Uuid**> | The item's base/default milk: the `milk_type` addon whose ingredient matches the item recipe's milk ingredient. The online customizer pre-selects it (mirrors the POS default-milk selection). `None` when the item has no milk in its recipe or no matching milk addon exists. | [optional]
**description** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**image_url** | Option<**String**> |  | [optional]
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**optionals** | [**Vec<models::DeliveryOptionalField>**](DeliveryOptionalField.md) |  | 
**price** | **i32** |  | 
**sizes** | [**Vec<models::DeliveryMenuSize>**](DeliveryMenuSize.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


