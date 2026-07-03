# BranchInventoryItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**below_reorder** | **bool** |  | 
**branch_id** | **uuid::Uuid** |  | 
**cost_per_unit** | Option<**f64**> | Piastres per unit; `null` ⟺ cost never entered. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**current_stock** | **f64** |  | 
**description** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**last_counted_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When this item was last reconciled by a finalized stock count; `null` = never counted. Drives the \"count due\" signal on the inventory home. | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**par_max** | Option<**f64**> | Order-up-to level (bring stock back up to this when reordering). | [optional]
**par_min** | Option<**f64**> | Reorder point (order when on-hand ≤ this). Falls back to reorder_threshold. | [optional]
**reorder_threshold** | **f64** |  | 
**unit** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


