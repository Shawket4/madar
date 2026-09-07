# StoredTurn

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**answer** | Option<**String**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**kind** | **String** | `answer` | `clarify` | `incomplete`. | 
**provider** | Option<**String**> |  | [optional]
**question** | **String** |  | 
**seq** | **i32** |  | 
**specs** | Option<**serde_json::Value**> | The queries that produced the answer — `[{title, preset_id, spec}]`. Re-running these is how a reopened conversation shows CURRENT figures rather than the numbers that were true when it was first asked. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


