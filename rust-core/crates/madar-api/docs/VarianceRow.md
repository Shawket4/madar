# VarianceRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**book_qty** | **f64** | Book stock the difference is measured against (at finalize). | 
**category_name** | **String** |  | 
**counted_qty** | Option<**f64**> |  | [optional]
**ingredient_name** | **String** |  | 
**is_flagged** | **bool** | True when |difference| exceeds the org threshold (or appears/vanishes from zero). | 
**opening_qty** | **f64** | Book stock when the count opened. | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**unit** | **String** |  | 
**unit_cost** | Option<**i64**> |  | [optional]
**variance** | Option<**f64**> | counted − book. | [optional]
**variance_reason** | Option<**String**> |  | [optional]
**variance_value** | Option<**i64**> | variance × unit_cost in piastres; `null` when cost unknown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


