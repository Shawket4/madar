# ShrinkageRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ingredient_name** | **String** |  | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**reason** | **String** | The variance reason captured at finalize, or `unexplained` when none. | 
**shrinkage_qty** | **f64** | Quantity lost (positive number) from negative stock-count differences. | 
**shrinkage_value** | Option<**i64**> | Valued shrinkage in piastres; `null` when any contributing cost unknown. | [optional]
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


