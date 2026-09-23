# OrderItemAddon

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addon_item_id** | **uuid::Uuid** |  | 
**addon_name** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**line_cost** | Option<**i64**> | Ingredient cost of this addon line in piastres. `null` ⟺ unknown, or a swap addon (its cost lives in the item's recipe cost). | [optional]
**line_total** | **i32** |  | 
**name_translations** | **serde_json::Value** |  | 
**order_item_id** | **uuid::Uuid** |  | 
**quantity** | **i32** |  | 
**staff_comp_minor** | Option<**i32**> | The part of a staff drink's comp this pick absorbed (whole line), already taken off `line_total`. 0 everywhere else. | [optional]
**unit_price** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


