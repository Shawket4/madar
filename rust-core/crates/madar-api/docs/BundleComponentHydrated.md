# BundleComponentHydrated

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**bundle_id** | **uuid::Uuid** |  | 
**id** | **uuid::Uuid** |  | 
**item_cost** | **i64** | Cost of the component (at its base size) in piastres. When `item_cost_missing` is true this is a PARTIAL figure (unknown = 0 on the wire for old-client compat) — display it as unknown, not as money. | 
**item_cost_missing** | Option<**bool**> | True when the component's cost could not be fully resolved. | [optional]
**item_id** | **uuid::Uuid** |  | 
**item_name** | **String** |  | 
**item_price** | **i32** |  | 
**position** | **i32** |  | 
**quantity** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


