# IngredientUsage

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**archived_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**ingredient_id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**needs_confirmation** | **bool** | `usages` or `stock` is non-empty: an archive must send `confirm: true`. | 
**never_used** | **bool** | Nothing references it at all, history included (no movement, recipe, PO, count, transfer or waste row), so a delete loses nothing. | 
**stock** | [**Vec<models::IngredientBranchStock>**](IngredientBranchStock.md) | Branches holding non-zero stock of it. Archiving leaves the balances alone; such a branch keeps seeing it in counts until it reaches zero. | 
**unit** | **String** |  | 
**usages** | [**Vec<models::IngredientUsageRef>**](IngredientUsageRef.md) | Active recipes, add-on/option lines, swaps, bases, packaging rules and open documents that reference it. Archiving does NOT change them: those recipes keep deducting and costing the ingredient. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


