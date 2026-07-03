# BranchMenuOverrideInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**is_available** | Option<**bool**> |  | [optional]
**menu_item_id** | **uuid::Uuid** |  | 
**price_override** | Option<**i32**> | Branch price in piastres; null inherits the org catalog base_price. | [optional]
**sizes** | Option<[**Vec<models::BranchSizeOverrideInput>**](BranchSizeOverrideInput.md)> | Per-size branch prices. `null`/omitted → leave existing size overrides untouched; a list → REPLACE the item's size overrides with exactly that set (empty clears them). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


