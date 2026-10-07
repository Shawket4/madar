# PoLineInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**line_cost** | Option<**i64**> | Piastres for the whole line, as invoiced. Preferred: the unit cost is derived from it exactly (12 000 g for 548.16 EGP is 4.568 piastres/g, where a whole-piastre unit cost made it 5 and the order 600.00). | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**purchase_unit** | **String** |  | 
**quantity_ordered** | **f64** |  | 
**unit_cost** | Option<**i64**> | Piastres per purchase unit, for clients that predate `line_cost`. Ignored when `line_cost` is sent; one of the two is required. | [optional]
**units_per_purchase_unit** | Option<**f64**> | Stock units per purchase unit. Ignored when `purchase_unit` is a known inventory unit (the factor is derived from the ingredient's base unit). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


