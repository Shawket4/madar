# RecipeBaseLineOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**ingredient_id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**quantity** | **String** | Base-unit quantity as a string (numeric fidelity). | 
**size_label** | Option<**String**> | `null` = applies to every size; else only to sizes with this exact label (and wins over a `null` line for the same ingredient). | [optional]
**sort** | **i32** |  | 
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


