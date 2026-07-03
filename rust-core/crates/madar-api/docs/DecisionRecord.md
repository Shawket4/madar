# DecisionRecord

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**decided_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**decided_by** | **uuid::Uuid** |  | 
**decision** | [**models::Decision**](Decision.md) |  | 
**id** | **uuid::Uuid** |  | 
**notes** | Option<**String**> |  | [optional]
**suggestion_id** | **uuid::Uuid** |  | 
**suggestion_kind** | [**models::SuggestionKind**](SuggestionKind.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


