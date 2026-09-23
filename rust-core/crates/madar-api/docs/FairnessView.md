# FairnessView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accepted_4w** | **i64** |  | 
**branches** | [**Vec<models::BranchFairness>**](BranchFairness.md) | The same, branch by branch, each with its own gap flag. | 
**decided_4w** | **i64** | Suggestions managers decided in the last 4 weeks, and how many they accepted. | 
**learning_frozen** | **bool** | Learning is paused at some branch. | 
**month** | **chrono::NaiveDate** |  | 
**rows** | [**Vec<models::FairnessRow>**](FairnessRow.md) | Night share by gender against stated willingness, the whole business. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


