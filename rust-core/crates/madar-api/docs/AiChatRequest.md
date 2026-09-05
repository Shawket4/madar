# AiChatRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**conversation_id** | Option<**uuid::Uuid**> | Continue a stored conversation. When set, history is loaded from the server and `history` below is ignored — this is the path that gives resumable chats and unlimited, compacted context.  Omit it to start a new conversation; the response says which one was created. | [optional]
**history** | Option<[**Vec<models::HistoryTurn>**](HistoryTurn.md)> | Recent prior turns, oldest first. The stateless fallback, kept for clients that manage their own window and for one-off questions. Ignored when `conversation_id` is set. The server caps it regardless. | [optional]
**locale** | Option<**String**> | Answer language — \"en\" or \"ar\" (default \"en\"). Drives translated labels and the reply language. | [optional]
**question** | **String** | The merchant's plain-language question, e.g. \"top 5 products last month\" or \"أعلى ٥ منتجات الشهر الماضي\". | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


