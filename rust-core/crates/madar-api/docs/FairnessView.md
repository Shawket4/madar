# FairnessView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accepted_4w** | **i64** |  | 
**decided_4w** | **i64** | Suggestions managers decided in the last 4 weeks, and how many they accepted. | 
**learning_frozen** | **bool** | Learning is paused: under 40% accepted over 4 weeks. | 
**month** | **chrono::NaiveDate** |  | 
**rows** | [**Vec<models::FairnessRow>**](FairnessRow.md) | Night share by gender against stated willingness. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


