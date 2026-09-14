# SnapshotCursor

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**after_seq** | **i64** | Ledger rows with `seq` above this come next. | 
**horizon** | **i64** |  | 
**started_at** | **String** | When the snapshot began (RFC 3339): a till that closes while the pages are fetched keeps its rows in the later pages. | 
**window_from** | **String** | The ledger window start of this snapshot (RFC 3339). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


