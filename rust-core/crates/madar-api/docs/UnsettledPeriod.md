# UnsettledPeriod

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ends_on** | **chrono::NaiveDate** |  | 
**net_total_piastres** | **i64** | The month's net pay: live for a draft, the frozen payslips once approved. | 
**paid_count** | **i64** | Payslips marked paid (a 'none' mark counts); 0 for a draft. | 
**people** | **i64** | People on the month's payroll. | 
**period_id** | **uuid::Uuid** |  | 
**starts_on** | **chrono::NaiveDate** |  | 
**status** | **String** | `draft` (never approved) · `generated` (approved, someone unpaid) | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


