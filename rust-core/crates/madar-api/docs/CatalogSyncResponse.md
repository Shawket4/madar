# CatalogSyncResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**catalog_revision** | **i64** |  | 
**changed** | **bool** | `false` when `since` equals the current revision (client is up to date; `items`/`ingredients` are then empty). `true` ⇒ the full payload follows. | 
**ingredients** | Option<[**Vec<models::SyncIngredient>**](SyncIngredient.md)> |  | [optional]
**items** | Option<[**Vec<models::SyncItem>**](SyncItem.md)> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


