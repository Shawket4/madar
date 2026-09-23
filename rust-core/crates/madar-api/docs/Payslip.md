# Payslip

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absent_days** | **f64** |  | 
**advance_installment_piastres** | **i64** |  | 
**base_salary_piastres** | **i64** |  | 
**bonuses_piastres** | **i64** |  | 
**breakdown** | Option<**serde_json::Value**> |  | 
**carry_out_piastres** | **i64** | What deductions exceeded pay by; carried into the next payslip (PAY-12). | 
**deductions_piastres** | **i64** |  | 
**generated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**late_minutes** | **i32** |  | 
**leave_days** | **f64** |  | 
**net_piastres** | **i64** |  | 
**org_id** | **uuid::Uuid** |  | 
**overtime_minutes** | **i32** |  | 
**overtime_piastres** | **i64** |  | 
**paid_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**paid_method** | Option<**String**> | Paid by `cash` · `bank` · `wallet` (PAY-7); null until marked paid. | [optional]
**payroll_period_id** | **uuid::Uuid** |  | 
**period_end** | Option<**chrono::NaiveDate**> |  | [optional]
**period_name** | Option<**String**> | The period this covers, denormalised. A payslip identified only by its generation timestamp is unreadable — two months run on the same day would be indistinguishable to the employee looking at them. | [optional]
**period_start** | Option<**chrono::NaiveDate**> |  | [optional]
**user_id** | **uuid::Uuid** |  | 
**user_name** | Option<**String**> |  | [optional]
**worked_days** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


