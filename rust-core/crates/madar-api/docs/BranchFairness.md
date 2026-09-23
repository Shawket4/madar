# BranchFairness

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accepted** | **i64** |  | 
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**by_default_decided** | **i64** | Suggestions the gender default decided, of those decided in the month. | 
**decided** | **i64** |  | 
**flagged** | **bool** | Over 20 points (design §4.2). | 
**gap_points** | **i64** | The widest gap, in percentage points, between a gender's share of the night shifts and its share of stated willingness (of headcount when nobody stated any). | 
**learning_frozen** | **bool** | Learning is paused at this branch: under 40% accepted over 4 weeks. | 
**rows** | [**Vec<models::FairnessRow>**](FairnessRow.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


