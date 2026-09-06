# ConversationDetail

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**compacted** | **bool** | True once older turns have been folded into a summary — surfaced so a client can say \"earlier messages condensed\" rather than appearing to have lost them. | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**last_turn_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**title** | **String** |  | 
**turn_count** | **i32** |  | 
**condensed** | Option<**String**> | The running summary of everything before the verbatim window. Returned so the UI can show what was condensed instead of a silent gap. | [optional]
**turns** | [**Vec<models::StoredTurn>**](StoredTurn.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


