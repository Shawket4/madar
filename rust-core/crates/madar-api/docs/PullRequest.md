# PullRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**limit** | Option<**i64**> | Page size for incremental pulls, 1..5000 (default 2000). | [optional]
**types** | Option<**Vec<String>**> | Full-fetch ONLY these types (checksum self-heal). Invalid with `since`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


