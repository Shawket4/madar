# SyncOption

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**is_available** | **bool** | Effective availability (branch_channel → branch → channel → TRUE). | 
**name** | **String** |  | 
**price** | **i32** | Effective price in piastres (branch_channel → branch → channel → catalog default). | 
**recipe** | [**Vec<models::SyncRecipeLine>**](SyncRecipeLine.md) |  | 
**replaces_ingredient_id** | Option<**uuid::Uuid**> | The org_ingredient this option swaps out, if it is a swap-style option. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


