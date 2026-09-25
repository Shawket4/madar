# CombinedItemSalesRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**item_id** | **uuid::Uuid** |  | 
**item_name** | **String** |  | 
**item_name_translations** | **serde_json::Value** |  | 
**standalone_qty** | **i64** | Equal to `total_qty` since combos were removed (it used to exclude units sold inside a combo). Kept so dashboards built before still render. | 
**total_qty** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


