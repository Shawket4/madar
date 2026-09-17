# OptionRecipeLineInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ingredient_id** | **uuid::Uuid** |  | 
**quantity** | **f64** |  | 
**size_label** | Option<**String**> | Size this amount is for (`Cup`, `Can`); `null`/absent = every size. At order time a line for the ordered size's exact label replaces the `null` line for the same ingredient. Legacy tills only ever see the `null` lines. | [optional]
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


