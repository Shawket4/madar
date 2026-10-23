# ReplayBatchResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**body** | Option<**serde_json::Value**> | The single-op call's JSON body (its ack, or its error body). | [optional]
**index** | **u32** | The op's position in `ops`. | 
**outcome** | [**models::ReplayOutcome**](ReplayOutcome.md) |  | 
**status** | Option<**u32**> | The HTTP status the single-op call would have answered (absent when skipped). | [optional]
**sync_seq** | Option<**i64**> | The single-op call's `X-Madar-Sync-Seq`, when it carried one. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


