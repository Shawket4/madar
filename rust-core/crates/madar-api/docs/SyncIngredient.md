# SyncIngredient

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> | The ingredient's category (additive, B12), so the POS can mirror the resolver's \"extras follow the drink's choice\" pass by slug. | [optional]
**category_slug** | Option<**String**> | Slug of [`Self::category_id`] (`milk`, `coffee_bean`, `packaging`, …). | [optional]
**id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


