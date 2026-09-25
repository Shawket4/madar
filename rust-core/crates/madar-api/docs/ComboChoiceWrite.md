# ComboChoiceWrite

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**id** | Option<**uuid::Uuid**> | The choice's id, to keep it on an edit; omit for a new choice. | [optional]
**included_size_label** | Option<**String**> | The size the combo price covers; `null` = the item's cheapest active size. | [optional]
**menu_item_id** | Option<**uuid::Uuid**> |  | [optional]
**size_surcharges** | Option<[**Vec<models::SizeSurcharge>**](SizeSurcharge.md)> |  | [optional]
**sort** | Option<**i32**> |  | [optional]
**surcharge** | Option<**i32**> | Per pick unit, piastres (C9 \"per-choice surcharge\"). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


