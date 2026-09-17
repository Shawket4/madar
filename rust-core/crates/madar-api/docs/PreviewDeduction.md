# PreviewDeduction

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_slug** | **String** |  | 
**ingredient_id** | Option<**uuid::Uuid**> |  | [optional]
**name** | **String** |  | 
**note** | Option<**String**> | `swapped from X` | `follows the chosen X` | `skipped on dine-in`. | [optional]
**quantity** | **f64** |  | 
**skipped** | **bool** | Shown but not deducted (dine-in packaging). | 
**source** | **String** | `recipe` | `swap` | `option` | `packaging`. | 
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


