# PullResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**asset_bundle** | Option<[**models::AssetBundleRef**](AssetBundleRef.md)> | Full responses only: the latest built base bundle, or null. | [optional]
**changes** | Option<[**Vec<models::PullChange>**](PullChange.md)> |  | [optional]
**checksums** | Option<[**std::collections::HashMap<String, models::TypeChecksum>**](TypeChecksum.md)> |  | [optional]
**data** | Option<**serde_json::Value**> |  | [optional]
**full** | **bool** |  | 
**has_more** | **bool** |  | 
**ledger_window** | Option<[**models::LedgerWindow**](LedgerWindow.md)> |  | [optional]
**next** | Option<**i64**> |  | [optional]
**resync_required** | Option<**bool**> |  | [optional]
**server_time** | **String** |  | 
**since** | Option<**i64**> |  | [optional]
**snapshot_cursor** | Option<[**models::SnapshotCursor**](SnapshotCursor.md)> | A paged full snapshot with more pages: send it back as `snapshot_cursor`. State types, checksums and the asset bundle come on the FIRST page only; `types` on each page lists what that page covers. | [optional]
**types** | Option<**Vec<String>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


