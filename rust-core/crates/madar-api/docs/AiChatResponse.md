# AiChatResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**kind** | **Kind** |  (enum: incomplete) | 
**results** | [**Vec<models::ResultBlock>**](ResultBlock.md) |  | 
**text** | **String** |  | 
**question** | **String** |  | 
**conversation_id** | Option<**uuid::Uuid**> | The conversation this turn belongs to. Present whenever the turn was stored — send it back on the next message to continue. | [optional]
**provider** | **String** | Which model answered. | 
**timezone** | **String** | The timezone every date in the answer is expressed in. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


