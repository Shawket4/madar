# ReplayBatchRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ops** | **Vec<serde_json::Value>** | Queued ops, oldest first: each exactly the body `POST /sync/replay` takes (`op`, the actor, `request`, optional `approval`, ...). | 
**protocol** | Option<**u32**> | The sync protocol the till speaks; 2 when absent (this route is v2). | [optional]
**stop_on_error** | Option<**bool**> | Stop at the first op that does not succeed (default true). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


