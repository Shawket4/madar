# ValuationRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cost_per_unit** | Option<**i64**> | Piastres per unit; `null` ⟺ unknown. | [optional]
**current_stock** | **f64** |  | 
**ingredient_name** | **String** |  | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**unit** | **String** |  | 
**value** | Option<**i64**> | current_stock × cost_per_unit in piastres; `null` when cost unknown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


