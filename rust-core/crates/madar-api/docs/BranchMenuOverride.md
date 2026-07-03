# BranchMenuOverride

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**is_available** | **bool** | False disables the item at this branch (excluded from the branch menu). | 
**menu_item_id** | **uuid::Uuid** |  | 
**price_override** | Option<**i32**> | Branch price in piastres; null inherits the org catalog base_price. | [optional]
**sizes** | Option<[**Vec<models::BranchSizeOverride>**](BranchSizeOverride.md)> | Per-size branch prices for this item (empty when none). Availability is item-level. | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


