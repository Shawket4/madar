# PackagingRuleLineOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ingredient_id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**quantity** | **String** | Base-unit quantity as a string. | 
**sort** | **i32** |  | 
**unit** | **String** |  | 
**usable_quantity** | **String** | The usable amount before yield loss, like `RecipeLineOut::usable_quantity`: what an editor shows and sends back (a line sent back unchanged keeps its stored `quantity`). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


