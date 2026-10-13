# GroupOptionRecipeLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ingredient_id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**quantity** | **f64** |  | 
**size_label** | Option<**String**> | `null` = the generic line (every size); else the per-size amount for that size label (menu modeling B9). The editor must round-trip it on save. | [optional]
**unit** | **String** |  | 
**usable_quantity** | **f64** | The usable amount before yield loss: `quantity` × the ingredient's yield, 3 dp (madar-units `usable_qty`). What the editor shows and sends back; a line sent back unchanged keeps its stored `quantity`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


