# WidgetRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**key** | **String** | Caller-chosen key, echoed back so results can be matched to widgets. | 
**period** | Option<[**models::Period**](Period.md)> | Overrides the batch-level period for this widget alone. | [optional]
**preset** | Option<**String**> | A curated metric id from `GET /metrics/schema`. | [optional]
**spec** | Option<[**models::QuerySpec**](QuerySpec.md)> | A fully custom query. Same IR the AI agent produces. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


