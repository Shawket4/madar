# AddonItemIngredient

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> | The ingredient's category (additive, B12): lets the POS know an extra shot is a `coffee_bean` and follows the drink's chosen bean. | [optional]
**category_slug** | Option<**String**> | Slug of [`Self::category_id`] (`milk`, `coffee_bean`, `packaging`, …). | [optional]
**ingredient_name** | **String** |  | 
**ingredient_unit** | **String** |  | 
**org_ingredient_id** | Option<**uuid::Uuid**> |  | [optional]
**quantity_used** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


