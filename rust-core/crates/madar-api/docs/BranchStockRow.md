# BranchStockRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**below_par** | **bool** |  | 
**branch_id** | **uuid::Uuid** |  | 
**category_id** | **uuid::Uuid** |  | 
**category_name** | **String** |  | 
**category_slug** | **String** |  | 
**cost_per_unit** | Option<**f64**> | This branch's actual (weighted-average) cost, falling back to the org standard cost. Piastres per unit; `null` ⟺ unknown. | [optional]
**description** | Option<**String**> |  | [optional]
**has_activity** | **bool** |  | 
**ingredient_name** | **String** |  | 
**last_counted_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Last finalized stock count that included this ingredient; `null` = never. | [optional]
**last_movement_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Last ledger movement of any kind; `null` = never. | [optional]
**on_hand** | **f64** | Book stock in the base unit. May be negative (sold past zero, flagged). | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**par_max** | Option<**f64**> | Order-up-to level for reorder suggestions. | [optional]
**par_min** | Option<**f64**> | Reorder point: below-par when `on_hand <= par_min` and `par_min > 0`. | [optional]
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


