# PullRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**ledger_page_size** | Option<**i64**> | Opt-in paging of a FULL snapshot's ledger rows (tills, orders, cash, refunds), 100..10000 rows a page. Absent = the whole snapshot in one response (what every older client gets). | [optional]
**limit** | Option<**i64**> | Page size for incremental pulls, 1..5000 (default 2000). | [optional]
**snapshot_cursor** | Option<[**models::SnapshotCursor**](SnapshotCursor.md)> | The `snapshot_cursor` of the previous page of a paged full snapshot. | [optional]
**types** | Option<**Vec<String>**> | Full-fetch ONLY these types (checksum self-heal). Invalid with `since`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


