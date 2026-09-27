# MixSlot

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> | The slot's names by language: the catalogue's when it has any, else what the sales stored (a deleted slot's). `{}` when neither has any. | [optional]
**picks** | [**Vec<models::MixPick>**](MixPick.md) |  | 
**slot_id** | Option<**uuid::Uuid**> | `null` for parts whose slot was deleted since. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


