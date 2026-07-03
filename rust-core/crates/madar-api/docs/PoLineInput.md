# PoLineInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**org_ingredient_id** | **uuid::Uuid** |  | 
**purchase_unit** | **String** |  | 
**quantity_ordered** | **f64** |  | 
**unit_cost** | **i64** | Piastres per purchase unit. | 
**units_per_purchase_unit** | Option<**f64**> | Stock units per purchase unit. Ignored when `purchase_unit` is a known inventory unit (the factor is derived from the ingredient's base unit). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


