# PublicComboChoice

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**available** | Option<**bool**> | `false`: the item is not sold on this menu right now (switched off at the branch or on the channel, or inactive). The page shows it greyed with \"Unavailable\" and never lets it be picked (an order that picks it is refused `COMBO_ITEM_UNAVAILABLE`); it has no `sizes` and is never the slot's default. Absent from an older server: available. | [optional]
**base_price** | **i32** | The included size's channel price (what the split weighs it by). | 
**image_url** | Option<**String**> |  | [optional]
**included_size_label** | **String** |  | 
**menu_item_id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**sizes** | [**Vec<models::PublicComboSize>**](PublicComboSize.md) |  | 
**surcharge** | **i32** | The choice's own surcharge, per pick unit. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


