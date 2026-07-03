# BranchAddonOverride

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addon_item_id** | **uuid::Uuid** |  | 
**branch_id** | **uuid::Uuid** |  | 
**is_available** | **bool** | False disables the addon at this branch (excluded from the branch addon list). | 
**price_override** | Option<**i32**> | Branch price in piastres; null inherits the org default_price. | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


