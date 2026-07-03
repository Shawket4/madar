# StocktakeItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_inventory_id** | Option<**uuid::Uuid**> |  | [optional]
**counted_by** | Option<**uuid::Uuid**> |  | [optional]
**counted_qty** | Option<**f64**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**expected_qty** | **f64** |  | 
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**note** | Option<**String**> |  | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**stocktake_id** | **uuid::Uuid** |  | 
**unit** | **String** |  | 
**unit_cost** | Option<**i64**> | Piastres per unit snapshot; `null` ⟺ unknown. | [optional]
**variance** | Option<**f64**> |  | [optional]
**variance_reason** | Option<**String**> | theft | spoilage | breakage | miscount | supplier_short | transfer_error | other. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


