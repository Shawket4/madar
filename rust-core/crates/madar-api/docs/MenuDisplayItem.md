# MenuDisplayItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**allowed_addon_ids** | **Vec<uuid::Uuid>** | The item's add-on allowlist (empty = no restriction). | 
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**combo** | Option<[**models::MenuDisplayCombo**](MenuDisplayCombo.md)> | A `combo` row's slots. | [optional]
**default_milk_addon_id** | Option<**uuid::Uuid**> | The item's base milk, pre-selected as on the till. | [optional]
**description** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**image_url** | Option<**String**> |  | [optional]
**kind** | **String** | `item` | `combo`. | 
**modifier_groups** | [**Vec<models::MenuDisplayModifierGroup>**](MenuDisplayModifierGroup.md) | Non-empty = the item's add-ons are exactly these groups' options. | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**optionals** | [**Vec<models::MenuDisplayOptional>**](MenuDisplayOptional.md) |  | 
**sizes** | [**Vec<models::MenuDisplaySize>**](MenuDisplaySize.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


