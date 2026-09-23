# ComputedPayslip

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absent_days** | **f64** |  | 
**advance_installment_piastres** | **i64** | What the advances WANT versus what the payslip can afford differ when net pay would go negative; this is the affordable figure, the one collected. | 
**base_piastres** | **i64** | After the calendar-day proration — what the days employed earn, at each day's salary (PAY-13). | 
**base_salary_piastres** | **i64** | The monthly salary in force at the end of the window. | 
**bonuses_piastres** | **i64** |  | 
**breakdown** | Option<**serde_json::Value**> | Line-by-line, so a preview can name each deduction rather than showing a lump sum nobody can argue with. | 
**carry_out_piastres** | **i64** | Deductions beyond what was earned: the payslip stops at zero and this carries into the next one as a debt (PAY-12). | 
**deductions_piastres** | **i64** |  | 
**employee_id** | **uuid::Uuid** |  | 
**late_minutes** | **i64** |  | 
**leave_days** | **f64** |  | 
**name** | **String** |  | 
**net_piastres** | **i64** |  | 
**overtime_minutes** | **i64** |  | 
**overtime_piastres** | **i64** |  | 
**worked_days** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


