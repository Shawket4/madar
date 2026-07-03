# VarianceRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**counted_qty** | Option<**f64**> |  | [optional]
**expected_qty** | **f64** |  | 
**ingredient_name** | **String** |  | 
**is_flagged** | **bool** | True when |difference| exceeds the org threshold (or appears/vanishes from zero). | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**unit** | **String** |  | 
**unit_cost** | Option<**i64**> |  | [optional]
**variance** | Option<**f64**> |  | [optional]
**variance_reason** | Option<**String**> | theft | spoilage | breakage | miscount | supplier_short | transfer_error | other. | [optional]
**variance_value** | Option<**i64**> | variance × unit_cost in piastres; `null` when cost unknown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


