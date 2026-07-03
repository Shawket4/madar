# OrderItemOptional

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cost** | Option<**i64**> | Ingredient cost per parent-item unit in piastres. `null` ⟺ unknown or no ingredient linked. | [optional]
**field_name** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**ingredient_name** | Option<**String**> |  | [optional]
**ingredient_unit** | Option<**String**> |  | [optional]
**name_translations** | **serde_json::Value** |  | 
**optional_field_id** | Option<**uuid::Uuid**> |  | [optional]
**order_item_id** | **uuid::Uuid** |  | 
**org_ingredient_id** | Option<**uuid::Uuid**> |  | [optional]
**price** | **i32** |  | 
**quantity_deducted** | Option<**f64**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


