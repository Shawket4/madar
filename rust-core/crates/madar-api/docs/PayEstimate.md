# PayEstimate

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**advance_cap_piastres** | **i64** | The owner's cap on what this person may owe (AV-5), server-computed. | 
**advance_outstanding_piastres** | **i64** |  | 
**advance_room_piastres** | **i64** | How much more can be asked for as an advance (AV-5). | 
**on_payroll** | **bool** |  | 
**period_end** | **chrono::NaiveDate** |  | 
**period_start** | **chrono::NaiveDate** |  | 
**slip** | Option<[**models::ComputedPayslip**](ComputedPayslip.md)> | So far this period, from the same engine payroll uses (PAY-9). Null for someone not on payroll. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


