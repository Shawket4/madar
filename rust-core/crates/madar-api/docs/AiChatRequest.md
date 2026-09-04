# AiChatRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**history** | Option<[**Vec<models::HistoryTurn>**](HistoryTurn.md)> | Recent prior turns in this conversation (oldest → newest), so follow-ups like \"and last month?\" resolve. Send only the last few; the server caps the window regardless. | [optional]
**include_summary** | Option<**bool**> | When true, also return a one-sentence natural-language summary of the result (a second, small model call, answered in `locale`). Default false. | [optional]
**locale** | Option<**String**> | Answer language — \"en\" or \"ar\" (default \"en\"). Drives translated labels and the summary language. Usually the dashboard's active language. | [optional]
**question** | **String** | The merchant's plain-language question, e.g. \"top 5 products last month\" or \"أعلى ٥ منتجات الشهر الماضي\". | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


