# CurrentPayroll

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**history** | [**Vec<models::PayrollPeriod>**](PayrollPeriod.md) | Earlier periods, newest first. | 
**paid_count** | **i64** | How many payslips are marked paid (a 'none' mark counts). | 
**payslips** | [**Vec<models::Payslip>**](Payslip.md) | The frozen payslips once it has been generated. | 
**period** | [**models::PayrollPeriod**](PayrollPeriod.md) |  | 
**preview** | [**Vec<models::ComputedPayslip>**](ComputedPayslip.md) | A live computation while the period is still a draft. | 
**totals** | [**models::PayrollTotals**](PayrollTotals.md) | The run added up by the server (AT-3). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


