# StocktakeItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**book_qty** | **f64** | The baseline the difference is measured against: live book stock while the count is open, frozen at finalize. | 
**category_id** | **uuid::Uuid** |  | 
**category_name** | **String** |  | 
**counted_by** | Option<**uuid::Uuid**> |  | [optional]
**counted_qty** | Option<**f64**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**is_new** | **bool** | True when the branch had no stock activity for this ingredient when the count opened — counting it is what starts tracking it here. | 
**note** | Option<**String**> |  | [optional]
**opening_qty** | **f64** | Book stock when the count was opened (reference only). | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**stocktake_id** | **uuid::Uuid** |  | 
**unit** | **String** |  | 
**unit_cost** | Option<**i64**> | Piastres per unit snapshot; `null` ⟺ unknown. | [optional]
**variance** | Option<**f64**> | counted − book; `null` until counted. | [optional]
**variance_reason** | Option<**String**> | theft | spoilage | breakage | miscount | supplier_short | transfer_error | other. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


