# ErrorBody

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**code** | Option<**String**> | Stable, machine-readable code for the error classes a client must branch on programmatically (e.g. `ORG_SUSPENDED`). Omitted for the generic cases where the status code alone is enough. | [optional]
**error** | **String** | Human-readable error message. | 
**retry_after_seconds** | Option<**i64**> | How long to wait before trying again, in seconds. Present on a `PIN_THROTTLED` refusal, absent everywhere else, so the PIN pad can run a countdown rather than inventing one. | [optional]
**till** | Option<**serde_json::Value**> | The till a `TILL_OPEN_AT_OTHER_BRANCH` / `TILL_OPEN_ELSEWHERE` refusal is about (`TillBrief`). Omitted everywhere else. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


