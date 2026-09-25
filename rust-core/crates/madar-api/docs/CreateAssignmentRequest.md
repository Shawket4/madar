# CreateAssignmentRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | The branch whose board sets the pattern: a business-wide block is worked there every week (one of the person's branches, else 400 `EMPLOYEE_NOT_AT_BRANCH`). Omitted = the person's first branch. | [optional]
**day_of_week** | Option<**i32**> | 0 = Sunday … 6 = Saturday. Omit for \"every day\". | [optional]
**effective_from** | Option<**chrono::NaiveDate**> |  | [optional]
**effective_to** | Option<**chrono::NaiveDate**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


