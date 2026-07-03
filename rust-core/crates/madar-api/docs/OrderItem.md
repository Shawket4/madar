# OrderItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**bundle_id** | Option<**uuid::Uuid**> |  | [optional]
**bundle_unit_price** | Option<**i32**> |  | [optional]
**cost_missing** | **bool** | True when any cost component could not be resolved. | 
**deductions_snapshot** | Option<**serde_json::Value**> |  | 
**id** | **uuid::Uuid** |  | 
**item_name** | **String** |  | 
**line_cost** | Option<**i64**> | Full line COGS in piastres (recipe + addons + optionals + components). `null` ⟺ unknown. | [optional]
**line_total** | **i32** |  | 
**menu_item_id** | Option<**uuid::Uuid**> |  | [optional]
**name_translations** | **serde_json::Value** |  | 
**notes** | Option<**String**> |  | [optional]
**order_id** | **uuid::Uuid** |  | 
**quantity** | **i32** |  | 
**size_label** | Option<**String**> |  | [optional]
**unit_cost** | Option<**i64**> | Recipe-only cost per unit in piastres (incl. swaps). `null` ⟺ unknown or bundle line. | [optional]
**unit_price** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


