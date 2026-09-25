# PutDayRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | The branch whose board sets the day: a business-wide block is worked there (one of the person's branches, else 400 `EMPLOYEE_NOT_AT_BRANCH`). Omitted = each block stays where the date had it (a new one at the person's first branch). | [optional]
**employee_id** | **uuid::Uuid** |  | 
**on_date** | **chrono::NaiveDate** |  | 
**reason** | Option<**String**> |  | [optional]
**shifts** | [**Vec<models::DayBlock>**](DayBlock.md) | Every shift the person works that date; empty = a day off. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


