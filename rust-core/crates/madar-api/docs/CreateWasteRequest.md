# CreateWasteRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**note** | Option<**String**> |  | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**quantity** | **f64** |  | 
**reason** | **String** | expired | spoiled | damaged | overproduction | order_cancelled | theft | other (`order_cancelled` is normally auto-logged by void/cancel, not entered here) | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


