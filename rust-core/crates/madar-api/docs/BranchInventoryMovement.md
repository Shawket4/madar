# BranchInventoryMovement

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**balance_after** | Option<**f64**> |  | [optional]
**below_zero** | **bool** |  | 
**branch_id** | **uuid::Uuid** |  | 
**branch_inventory_id** | Option<**uuid::Uuid**> |  | [optional]
**branch_name** | Option<**String**> | Branch name; only populated by the all-branches waste roll-up (nil {branch_id}). `None` for single-branch queries that do not select it. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**created_by_name** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**movement_type** | **String** | inventory_movement_type: sale | void_restock | adjustment_add | adjustment_remove | waste | transfer_out | transfer_in | purchase_in | stock_count | 
**note** | Option<**String**> |  | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**quantity** | **f64** | Signed delta applied to stock (consumption negative, replenishment positive). | 
**reason** | Option<**String**> |  | [optional]
**source_id** | Option<**uuid::Uuid**> |  | [optional]
**source_type** | Option<**String**> |  | [optional]
**unit** | **String** |  | 
**unit_cost** | Option<**i64**> | Piastres per unit at movement time; `null` ⟺ unknown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


