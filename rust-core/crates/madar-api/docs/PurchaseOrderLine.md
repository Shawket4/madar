# PurchaseOrderLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**line_cost** | **i64** | Piastres for the whole line, as on the supplier's invoice. The unit cost is derived from it, never the other way round. | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**purchase_order_id** | **uuid::Uuid** |  | 
**purchase_unit** | **String** |  | 
**quantity_ordered** | **f64** |  | 
**quantity_received** | **f64** |  | 
**unit** | **String** | Ingredient's base stock unit. | 
**unit_cost** | **i64** | Piastres per PURCHASE unit, rounded to whole piastres (older readers; the truth is `line_cost`, the precise figure `unit_cost_exact`). | 
**unit_cost_exact** | **f64** | Piastres per PURCHASE unit, exact: `line_cost / quantity_ordered`. | 
**units_per_purchase_unit** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


