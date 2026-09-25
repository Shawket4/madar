# ComboSlotWrite

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**choices** | [**Vec<models::ComboChoiceWrite>**](ComboChoiceWrite.md) |  | 
**default_item_id** | Option<**uuid::Uuid**> | Pre-selected on the till and used for unpicked replays; must be one of the slot's choices (by id, or by its category). | [optional]
**default_size_label** | Option<**String**> |  | [optional]
**id** | Option<**uuid::Uuid**> | The slot's id, to keep it on an edit; omit for a new slot. | [optional]
**max** | **i32** | Picks allowed (1–10, ≥ min). | 
**min** | **i32** | Picks required (0–10). 0 = optional slot. | 
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | [optional]
**sort** | Option<**i32**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


