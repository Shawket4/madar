# NewExpenseAdvance

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | **i64** |  | 
**branch_id** | Option<**uuid::Uuid**> | Where it was handed over; defaults to the person's first branch. Must be a branch the caller may log at. | [optional]
**employee_id** | **uuid::Uuid** |  | 
**given_on** | Option<**chrono::NaiveDate**> | When the cash changed hands; defaults to today (AV-7). | [optional]
**purpose** | **String** |  | 
**via** | **String** | `safe` · `bank`. A till pay-out is tagged on the POS (AV-8), never logged here by hand (AV-10). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


