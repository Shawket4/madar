# ScheduledDay

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_name** | Option<**String**> | The branch each shift is worked at, when the employee has one assignment. | [optional]
**date** | **chrono::NaiveDate** |  | 
**published** | Option<**bool**> | The week is published at the person's branch. Unpublished weeks are drafts: they come back empty (SC-3). | [optional]
**shifts** | [**Vec<models::ResolvedShift>**](ResolvedShift.md) | Empty = a rest day, or a week not published yet. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


