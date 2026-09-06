# HistoryTurn

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**answer** | Option<**String**> | What the assistant replied. Optional so a client can send a partial log. | [optional]
**question** | **String** |  | 
**spec** | Option<[**models::QuerySpec**](QuerySpec.md)> | The query that produced that answer, from `results[].spec`. Optional so an older client, or a turn that ran no query, still works. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


