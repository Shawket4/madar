# RecordDecisionBody

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**decision** | **String** | accepted | rejected | ignored — kept as a string so invalid values yield a 400 instead of a deserialization error. | 
**notes** | Option<**String**> |  | [optional]
**suggestion_id** | **uuid::Uuid** |  | 
**suggestion_kind** | [**models::SuggestionKind**](SuggestionKind.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


