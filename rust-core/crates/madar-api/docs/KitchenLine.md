# KitchenLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**combo** | Option<[**models::KitchenComboTag**](KitchenComboTag.md)> | The combo this line is a part of (C12): each part routes to its own station, tagged with the combo's name. `null` for a plain line; old KDS builds ignore it. | [optional]
**menu_item_id** | Option<**uuid::Uuid**> |  | [optional]
**modifiers** | Option<**Vec<String>**> |  | [optional]
**name** | **String** |  | 
**notes** | Option<**String**> |  | [optional]
**qty** | **i32** |  | 
**size_label** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


