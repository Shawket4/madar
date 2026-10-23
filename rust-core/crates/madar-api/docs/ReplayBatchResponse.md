# ReplayBatchResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**applied** | **u32** | How many ops were applied. | 
**protocol** | **u32** | The negotiated sync protocol. | 
**results** | [**Vec<models::ReplayBatchResult>**](ReplayBatchResult.md) | One per op, in order. | 
**stopped_at** | Option<**u32**> | The index the batch stopped at, when it stopped early. | [optional]
**sync_seq** | Option<**i64**> | The highest `sync_seq` of the batch: a pull from here sees every op. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


