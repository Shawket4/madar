# ValuationRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cost_per_unit** | Option<**i64**> | Piastres per unit; `null` ⟺ unknown. | [optional]
**ingredient_name** | **String** |  | 
**on_hand** | **f64** |  | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**unit** | **String** |  | 
**value** | Option<**i64**> | on_hand × cost_per_unit in piastres; `null` when cost unknown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


