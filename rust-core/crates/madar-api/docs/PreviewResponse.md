# PreviewResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cost** | [**models::PreviewCost**](PreviewCost.md) |  | 
**deductions** | [**Vec<models::PreviewDeduction>**](PreviewDeduction.md) |  | 
**defaults** | **std::collections::HashMap<String, uuid::Uuid>** | Swap groups: group id → the option preselected by the recipe. | 
**price** | [**models::PreviewPrice**](PreviewPrice.md) |  | 
**quantity** | **i32** |  | 
**size_label** | Option<**String**> | The size the preview resolved (the request's, else the default size). | [optional]
**warnings** | [**Vec<models::ResolveWarning>**](ResolveWarning.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


